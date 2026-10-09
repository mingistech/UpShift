"""Real Apple GPU integration checks; run with .runtime/venv/bin/python."""
import importlib.util
import json
import os
from pathlib import Path
import signal
import stat
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
BRIDGE = ROOT / 'UpShift/Resources/upshift_bridge.py'
RUNTIME = Path(os.environ.get('UPSHIFT_TEST_RUNTIME', ROOT / '.runtime'))
BRIDGE = Path(os.environ.get('UPSHIFT_TEST_BRIDGE', BRIDGE))
spec = importlib.util.spec_from_file_location('bridge', BRIDGE)
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)


class PipelineTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        import imageio_ffmpeg
        cls.ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()
        (ROOT / 'work').mkdir(exist_ok=True)
        cls.folder = tempfile.TemporaryDirectory(prefix='pipeline-tests-', dir=ROOT / 'work')
        cls.directory = Path(cls.folder.name)

    @classmethod
    def tearDownClass(cls):
        cls.folder.cleanup()

    def make_source(self, name, rate='24', size='320x180', duration='0.5', audio=True):
        path = self.directory / name
        cmd = [self.ffmpeg, '-v', 'error', '-f', 'lavfi', '-i', f'testsrc2=size={size}:rate={rate}']
        if audio:
            cmd += ['-f', 'lavfi', '-i', 'sine=frequency=440:sample_rate=48000']
        cmd += ['-t', duration, '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-y', str(path)]
        subprocess.run(cmd, check=True, timeout=30)
        return path

    def command(self, source, destination, *extra):
        return [str(RUNTIME / 'venv/bin/python'), '-u', str(BRIDGE), '--runtime', str(RUNTIME),
                '--input', str(source), '--output', str(destination), *extra]

    def render(self, source, destination, *extra):
        process = subprocess.run(self.command(source, destination, *extra), capture_output=True, text=True, timeout=120)
        events = [json.loads(line) for line in process.stdout.splitlines()]
        return process.returncode, events

    def test_720p_to_1440p_with_audio_and_spaces(self):
        source = self.make_source('720p source with spaces.mp4', size='1280x720')
        output = self.directory / '1440p output.mp4'
        code, events = self.render(source, output)
        self.assertEqual(code, 0, events[-5:])
        self.assertEqual(events[-1]['type'], 'complete')
        before, after = bridge.inspect_video(source), bridge.inspect_video(output)
        bridge.validate_result(before, after)
        self.assertEqual((after['width'], after['height']), (2560, 1440))
        self.assertEqual(after['frames'], 12)
        self.assertEqual(after['pixel_format'], 'yuv420p')
        self.assertFalse(output.stat().st_flags & stat.UF_HIDDEN)

    def test_hidden_staging_flag_is_cleared_without_changing_other_flags_or_contents(self):
        output = self.directory / 'hidden-output.mp4'
        output.write_bytes(b'completed video')
        os.chflags(output, stat.UF_HIDDEN | stat.UF_NODUMP)
        bridge.make_output_visible(output)
        self.assertFalse(output.stat().st_flags & stat.UF_HIDDEN)
        self.assertTrue(output.stat().st_flags & stat.UF_NODUMP)
        self.assertEqual(output.read_bytes(), b'completed video')
        bridge.make_output_visible(output)  # Safe for already-visible files too.

    def test_fractional_fps_without_audio(self):
        source = self.make_source('fractional.mp4', rate='24000/1001', audio=False)
        output = self.directory / 'fractional-upscaled.mp4'
        code, events = self.render(source, output)
        self.assertEqual(code, 0, events[-5:])
        result = bridge.inspect_video(output)
        self.assertEqual(result['fps'], '24000/1001')
        self.assertEqual(result['audio'], [])

    def test_ai_compression_cleanup(self):
        source = self.make_source('cleanup.mp4', size='160x96', duration='0.25')
        output = self.directory / 'cleanup-upscaled.mp4'
        code, events = self.render(source, output, '--restore-compression')
        self.assertEqual(code, 0, events[-5:])
        self.assertTrue(any('Using Extra Restoration Model:' in e.get('message', '') for e in events))
        bridge.validate_result(bridge.inspect_video(source), bridge.inspect_video(output))

    def test_original_and_existing_destination_are_protected(self):
        source = self.make_source('protected.mp4')
        original = source.read_bytes()
        code, _ = self.render(source, source, '--replace')
        self.assertNotEqual(code, 0)
        self.assertEqual(source.read_bytes(), original)
        output = self.directory / 'existing.mp4'
        output.write_bytes(b'existing destination')
        code, _ = self.render(source, output)
        self.assertNotEqual(code, 0)
        self.assertEqual(output.read_bytes(), b'existing destination')
        invalid = self.directory / 'invalid.mp4'
        invalid.write_bytes(b'invalid video')
        code, _ = self.render(invalid, output, '--replace')
        self.assertNotEqual(code, 0)
        self.assertEqual(output.read_bytes(), b'existing destination')

    def test_cancel_keeps_destination_and_stops_children(self):
        source = self.make_source('cancel.mp4', size='1280x720', duration='5')
        output = self.directory / 'cancel-output.mp4'
        output.write_bytes(b'keep me')
        process = subprocess.Popen(self.command(source, output, '--replace'), stdout=subprocess.PIPE, text=True)
        child_pids = []
        try:
            # Wait for actual RVE inference, not just bridge startup.
            import selectors
            with selectors.DefaultSelector() as selector:
                selector.register(process.stdout, selectors.EVENT_READ)
                deadline = time.monotonic() + 60
                while time.monotonic() < deadline:
                    if not selector.select(timeout=1):
                        continue
                    line = process.stdout.readline()
                    if not line:
                        self.fail('Engine exited before the cancellation test.')
                    event = json.loads(line)
                    if event.get('message') == 'BACKEND: Rendering':
                        result = subprocess.run(['pgrep', '-P', str(process.pid)], capture_output=True, text=True)
                        child_pids = [int(pid) for pid in result.stdout.split()]
                        break
                else:
                    self.fail('Render did not begin within 60 seconds.')
            self.assertTrue(child_pids)
            process.send_signal(signal.SIGTERM)
            remaining, _ = process.communicate(timeout=15)
            self.assertEqual(process.returncode, 130, remaining)
            self.assertEqual(output.read_bytes(), b'keep me')
            self.assertEqual(list(self.directory.glob('.upshift-*')), [])
            for pid in child_pids:
                with self.assertRaises(ProcessLookupError):
                    os.kill(pid, 0)
        finally:
            if process.poll() is None:
                process.terminate()
                process.communicate(timeout=15)


if __name__ == '__main__':
    unittest.main(verbosity=2)
