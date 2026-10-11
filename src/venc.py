"""Параметри кодування відео для ffmpeg, спільні для follow.py, closeup.py і highlights.py.
VENC=hw — апаратний кодер Mac (VideoToolbox): у кілька разів швидше, файл трохи більший. VENC=sw — libx264.
За замовчуванням hw, якщо ffmpeg його має (Mac), інакше sw (хмара, Linux)."""
import os, subprocess, functools


@functools.lru_cache(None)
def _has_hw():
    try:
        return 'h264_videotoolbox' in subprocess.run(['ffmpeg', '-hide_banner', '-encoders'], capture_output=True, text=True).stdout
    except OSError:
        return False


def video_args(height=1080):
    mode = os.environ.get('VENC', 'hw' if _has_hw() else 'sw')
    if mode == 'hw':
        return ['-c:v', 'h264_videotoolbox', '-b:v', f'{max(4, height * 8 // 1080)}M', '-pix_fmt', 'yuv420p']
    return ['-c:v', 'libx264', '-preset', 'veryfast', '-crf', '23', '-pix_fmt', 'yuv420p']
