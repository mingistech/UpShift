"""Upshift's local RVE adapter. stdout is a newline-delimited JSON event stream."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import selectors
import signal
import stat
import subprocess
import sys
import tempfile
import time


class Cancelled(BaseException):
    pass


def emit(kind, **fields):
    print(json.dumps({"type": kind, **fields}), flush=True)


def make_output_visible(path):
    # iCloud can mark files created inside our hidden staging folder UF_HIDDEN.
    # Renaming the file does not clear that flag, so Finder still conceals it.
    hidden = getattr(stat, "UF_HIDDEN", 0)
    flags = getattr(path.stat(), "st_flags", 0)
    if flags & hidden:
        os.chflags(path, flags & ~hidden)


def cancelled(_signum, _frame):
    raise Cancelled()


def inspect_video(path, *, source=False):
    import av
    with av.open(str(path)) as container:
        if len(container.streams.video) != 1:
            raise ValueError("Choose a file with exactly one video track.")
        stream = container.streams.video[0]
        rate = stream.average_rate
        if not rate or rate <= 0:
            raise ValueError("The video has no usable frame rate.")
        if source and stream.codec_context.color_trc in (16, 18):
            raise ValueError("This first version supports SDR video. Convert HDR to SDR before upscaling.")
        width, height = stream.codec_context.width, stream.codec_context.height
        count, first, previous = 0, None, None
        tolerance = max(float(stream.time_base) * 1.1, 0.0001)
        for frame in container.decode(stream):
            if source and getattr(frame, "rotation", 0):
                raise ValueError("This video uses rotation metadata. Export it with rotation applied first.")
            if frame.pts is None:
                raise ValueError("The video has missing timestamps.")
            timestamp = float(frame.pts * frame.time_base)
            if previous is not None and abs(timestamp - previous - float(1 / rate)) > tolerance:
                raise ValueError("Variable frame rate video is not supported yet. Export a constant frame rate MP4 first.")
            if first is None:
                first = timestamp
            previous = timestamp
            count += 1
        if not count:
            raise ValueError("The video contains no decodable frames.")
        info = {"width": width, "height": height, "fps": str(rate), "frames": count,
                "codec": stream.codec_context.name, "start": first,
                "pixel_format": stream.codec_context.format.name}
    # Packet hashes verify audio was actually copied, including every audio track.
    with av.open(str(path)) as container:
        tracks = list(container.streams.audio)
        if source and any(s.codec_context.name not in {"aac", "mp3", "alac", "ac3", "eac3"} for s in tracks):
            raise ValueError("This audio codec cannot be copied to this MP4 preset. Export the source with AAC audio first.")
        hashes = {s.index: hashlib.sha256() for s in tracks}
        starts = {}
        for packet in container.demux(tracks) if tracks else []:
            if packet.size:
                hashes[packet.stream.index].update(bytes(packet))
                if packet.pts is not None:
                    starts.setdefault(packet.stream.index, float(packet.pts * packet.time_base))
        info["audio"] = [{"codec": s.codec_context.name, "sha256": hashes[s.index].hexdigest(),
                          "offset": starts.get(s.index, first) - first} for s in tracks]
    return info


def validate_result(source, result):
    if (result["width"], result["height"]) != (source["width"] * 2, source["height"] * 2):
        raise ValueError("The engine did not produce the expected 2× resolution.")
    if result["codec"] != "hevc" or result["fps"] != source["fps"] or result["frames"] != source["frames"]:
        raise ValueError("Output verification failed: codec, frame rate, or frame count changed.")
    if result["pixel_format"] != "yuv420p":
        raise ValueError("Output verification failed: the original preset requires 8-bit HEVC.")
    if len(result["audio"]) != len(source["audio"]):
        raise ValueError("Output verification failed: an audio track is missing.")
    for before, after in zip(source["audio"], result["audio"]):
        if (before["codec"], before["sha256"]) != (after["codec"], after["sha256"]):
            raise ValueError("Output verification failed: the original audio was not preserved.")
        if abs(before["offset"] - after["offset"]) > 0.005:
            raise ValueError("Output verification failed: audio timing changed.")


def stop_group(child):
    if child is None:
        return
    # The entire RVE session includes its FFmpeg children, even after RVE exits.
    try:
        os.killpg(child.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    try:
        child.wait(timeout=3)
    except subprocess.TimeoutExpired:
        pass
    try:
        os.killpg(child.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    child.wait()


def render_lines(child):
    """Read CR-delimited RVE progress without blocking cancellation or a watchdog."""
    pending = b""
    last_advance = time.monotonic()
    last_frame = -1
    with selectors.DefaultSelector() as selector:
        selector.register(child.stdout, selectors.EVENT_READ)
        while True:
            if time.monotonic() - last_advance > 300:
                raise ValueError("The engine made no progress for five minutes and was stopped. See processing details.")
            if not selector.select(timeout=1):
                continue
            chunk = os.read(child.stdout.fileno(), 4096)
            if not chunk:
                if pending.strip():
                    yield pending.decode("utf-8", errors="replace").strip()
                break
            pending += chunk.replace(b"\r", b"\n")
            while b"\n" in pending:
                raw, pending = pending.split(b"\n", 1)
                line = raw.decode("utf-8", errors="replace").strip()
                match = re.search(r"Current Frame: (\d+)", line)
                if match and int(match[1]) > last_frame:
                    last_frame = int(match[1])
                    last_advance = time.monotonic()
                if line:
                    yield line


def run(args):
    runtime = Path(args.runtime).resolve()
    config = json.loads((runtime / "engine.json").read_text())
    source_path = Path(args.input).resolve(strict=True)
    destination = Path(args.output).absolute()
    if destination.suffix.lower() != ".mp4":
        raise ValueError("Choose an MP4 output filename.")
    if destination.resolve() == source_path or (destination.exists() and os.path.samefile(source_path, destination)):
        raise ValueError("The output must be different from the original video.")
    if destination.exists() and not args.replace:
        raise ValueError("The output already exists. Choose another name.")
    emit("status", message="Checking source video…")
    info = inspect_video(source_path, source=True)
    emit("log", message=f"Source: {info['width']}×{info['height']} · {info['fps']} fps · {info['frames']} frames")
    import torch
    import imageio_ffmpeg
    if not torch.backends.mps.is_available():
        raise ValueError("Apple GPU processing is unavailable. Run Upshift on an Apple silicon Mac.")
    ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()
    backend = runtime / config["backend"]
    model = runtime / config["model"]
    if not backend.is_file() or not model.is_file():
        raise ValueError("The engine or model is missing. Run Scripts/setup-engine.sh again.")
    if hashlib.sha256(model.read_bytes()).hexdigest() != config["model_sha256"]:
        raise ValueError("The model file failed its integrity check. Run setup again.")
    restoration = None
    if args.restore_compression:
        if "restoration_model" not in config:
            raise ValueError("The cleanup model is not installed. Run Scripts/setup-engine.sh again.")
        restoration = runtime / config["restoration_model"]
        if not restoration.is_file() or hashlib.sha256(restoration.read_bytes()).hexdigest() != config["restoration_sha256"]:
            raise ValueError("The cleanup model failed its integrity check. Run setup again.")
    # Keep an existing destination intact until the complete render passes verification.
    with tempfile.TemporaryDirectory(prefix=".upshift-", dir=destination.parent) as scratch:
        scratch = Path(scratch)
        temporary = scratch / "render.mp4"
        # VideoToolbox's quality scale increases with quality (unlike x265 CRF).
        # Restore the original compact export preferred in the user's comparison.
        encoder = (f"-c:v hevc_videotoolbox -allow_sw 0 -q:v 65 -profile:v main -tag:v hvc1 "
                   f"-pix_fmt yuv420p -r {info['fps']} -c:a copy -sn -movflags +faststart")
        emit("log", message="Original export: HEVC Main · quality 65 · 8-bit SDR · original audio")
        command = [sys.executable, "-u", str(backend), "-i", str(source_path), "-o", str(temporary),
                   "--backend", "pytorch", "--device", "mps", "--precision", "float32",
                   "--upscale_model", str(model), "--interpolate_factor", "1",
                   "--scene_detect_method", "none", "--ffmpeg_path", ffmpeg,
                   "--custom_encoder", encoder, "--cwd", str(scratch)]
        if restoration:
            command += ["--extra_restoration_models", str(restoration)]
            emit("log", message="AI compression cleanup: DeH264 RTMoSR before upscaling")
        child = None
        try:
            emit("status", message="Loading model on Apple GPU…")
            child = subprocess.Popen(command, cwd=scratch, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                     stdin=subprocess.DEVNULL, start_new_session=True)
            for line in render_lines(child):
                line = line.strip()
                if not line:
                    continue
                match = re.search(r"FPS: (\S+) Current Frame: (\d+) ETA: (\S+)", line)
                if match:
                    fps, frame, eta = match.groups()
                    emit("progress", fraction=min(int(frame) / info["frames"], 0.99),
                         message=f"Upscaling · {fps} fps · {eta} remaining")
                else:
                    emit("log", message=line)
            code = child.wait()
            encoder_log = scratch / "ffmpeg_log.txt"
            if encoder_log.exists() and encoder_log.stat().st_size:
                emit("log", message=encoder_log.read_text(errors="replace")[-8000:])
            if code:
                raise ValueError(f"RVE stopped with code {code}. See processing details.")
            emit("status", message="Verifying resolution, frame rate, and audio…")
            validate_result(info, inspect_video(temporary))
            make_output_visible(temporary)
            # Signals are deferred through the tiny commit step so cancellation cannot
            # report failure after a successfully verified output has been installed.
            old_mask = signal.pthread_sigmask(signal.SIG_BLOCK, {signal.SIGTERM, signal.SIGINT})
            try:
                if args.replace:
                    os.replace(temporary, destination)
                else:
                    os.link(temporary, destination)  # Atomic no-overwrite commit.
                    temporary.unlink()
                make_output_visible(destination)
                emit("complete", output=str(destination), message="Your upscaled video is ready.")
                signal.signal(signal.SIGTERM, signal.SIG_IGN)
                signal.signal(signal.SIGINT, signal.SIG_IGN)
            finally:
                signal.pthread_sigmask(signal.SIG_SETMASK, old_mask)
        finally:
            stop_group(child)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--runtime", required=True)
    parser.add_argument("--input", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--replace", action="store_true")
    parser.add_argument("--restore-compression", action="store_true")
    args = parser.parse_args()
    signal.signal(signal.SIGTERM, cancelled)
    signal.signal(signal.SIGINT, cancelled)
    try:
        run(args)
    except Cancelled:
        emit("cancelled", message="Cancelled.")
        return 130
    except Exception as error:
        emit("error", message=str(error))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
