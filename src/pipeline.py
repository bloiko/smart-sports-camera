"""Увесь конвеєр однією командою: відео → готовий ролик, метрики, перевірки.

Використання:
  python src/pipeline.py VIDEO OUT_DIR [--step 5] [--checklist specs/checklists/match1.json]
                         [--no-render] [--range A-B] [--from STEP] [--highlights]

Кроки (кожен пропускається, якщо його результат уже є; перервані детекція і пошук м'яча
продовжуються з останнього кадру — можна просто запустити команду ще раз):
  detect     detect.py         → OUT/detections.jsonl
  pass1      follow.py         → OUT/pass1/camera_path.npz (куди дивиться камера)
  window     ball_window.py ×2 → OUT/ball_base.jsonl, OUT/ball_v02.jsonl
  merge      merge_balls.py    → OUT/balls.jsonl
  bgdiff     ball_bgdiff.py    → OUT/detections.bg.jsonl, OUT/balls.bg.jsonl
  final      follow.py         → OUT/final/out_follow.mp4, out_debug.mp4, metrics.json, ...
  checks     check_goals.py (з --checklist), ball_sheet.py → OUT/final/ball_sheet.jpg
  highlights highlights.py (з --highlights) → OUT/highlights/
--from STEP: перерахувати цей крок і всі наступні (наприклад, --from final після зміни follow.py).
"""
import json, os, subprocess, sys, time
import cv2

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC_DIR = os.path.join(ROOT, 'src')
PY = sys.executable
STEPS = ['detect', 'pass1', 'window', 'merge', 'bgdiff', 'final', 'checks', 'highlights']
# моделі пошуку м'яча у вікні та їхні пороги (об'єднання — merge_balls.py)
BALL_MODELS = [('ball_base.jsonl', 'yolo11s.pt', 0.25), ('ball_v02.jsonl', os.path.join(ROOT, 'models', 'ball_v02.pt'), 0.4)]


def arg(name, default=None):
    return sys.argv[sys.argv.index(name) + 1] if name in sys.argv else default


def run(cmd, env=None, log=None):
    print('$', ' '.join(os.path.relpath(c, ROOT) if os.path.isabs(c) else c for c in cmd), flush=True)
    t0 = time.time()
    out = open(log, 'a') if log else None
    r = subprocess.run(cmd, cwd=ROOT, env={**os.environ, **(env or {})}, stdout=out, stderr=subprocess.STDOUT if out else None)
    if r.returncode: sys.exit(f'step failed ({r.returncode}): {" ".join(cmd)}' + (f'; see {log}' if log else ''))
    print(f'  {time.time() - t0:.0f} s', flush=True)


def resume_frame(path, step):
    """Останній записаний кадр у jsonl (обрізаний останній рядок прибирається) → з якого кадру продовжити."""
    if not os.path.exists(path): return 0
    good = []
    for line in open(path):
        try: good.append(json.loads(line))
        except json.JSONDecodeError: break
    with open(path, 'w') as f:
        for r in good: f.write(json.dumps(r) + '\n')
    return good[-1]['frame'] + step if good else 0


def main():
    video, out = os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2])
    step = int(arg('--step', 5)); checklist = arg('--checklist')
    os.makedirs(out, exist_ok=True)
    n_frames = int(cv2.VideoCapture(video).get(cv2.CAP_PROP_FRAME_COUNT))   # приблизно (для логу)
    state = {'redo': STEPS.index(arg('--from')) if arg('--from') else len(STEPS)}
    P = lambda *a: os.path.join(out, *a)
    S = lambda name: os.path.join(SRC_DIR, name)
    done = lambda i, path: i < state['redo'] and os.path.exists(path)
    def ran(i): state['redo'] = min(state['redo'], i + 1)    # крок перераховано → наступні теж
    t_all = time.time()

    # 1. детекція гравців і м'яча (з продовженням)
    det = P('detections.jsonl')
    if state['redo'] <= 0 and os.path.exists(det + '.done'): os.remove(det + '.done')
    if not os.path.exists(det + '.done'):           # маркер: крок дійшов до кінця відео
        start = 0 if state['redo'] <= 0 else resume_frame(det, step)
        print(f'[detect] from frame {start} of {n_frames}', flush=True)
        run([PY, S('detect.py'), video, det, str(step)] + ([str(start)] if start else []), log=P('detect.log')); ran(0)
        open(det + '.done', 'w').close()
    else:
        print('[detect] done')

    # 2. перший прохід камери: куди шукати м'яч
    if not done(1, P('pass1', 'camera_path.npz')):
        print('[pass1]', flush=True)
        run([PY, S('follow.py'), video, det, P('pass1'), '--no-render'], log=P('pass1.log')); ran(1)
    else:
        print('[pass1] done')

    # 3. пошук м'яча у збільшеному вікні, кожна модель окремо (з продовженням)
    for fname, model, _ in BALL_MODELS:
        path = P(fname)
        if state['redo'] <= 2:
            for f in (path, path + '.done'):
                if os.path.exists(f): os.remove(f)
        if not os.path.exists(path + '.done'):
            start = resume_frame(path, step)
            print(f'[window] {fname} from frame {start}', flush=True)
            run([PY, S('ball_window.py'), video, P('pass1', 'camera_path.npz'), path, str(step)] + ([str(start)] if start else []),
                env={'BALL_MODEL': model}, log=P(fname.replace('.jsonl', '.log'))); ran(2)
            open(path + '.done', 'w').close()
        else:
            print(f'[window] {fname} done')

    # 4. об'єднання моделей
    if not done(3, P('balls.jsonl')):
        print('[merge]', flush=True)
        run([PY, S('merge_balls.py'), P('balls.jsonl')] + [f'{P(f)}:{t}' for f, _, t in BALL_MODELS]); ran(3)
    else:
        print('[merge] done')

    # 5. різниця з фоном (букви на газоні, манекени)
    if not done(4, P('balls.bg.jsonl')) or os.path.getmtime(P('balls.bg.jsonl')) < os.path.getmtime(P('balls.jsonl')):
        print('[bgdiff]', flush=True)
        run([PY, S('ball_bgdiff.py'), video, det, P('balls.jsonl')], log=P('bgdiff.log')); ran(4)
    else:
        print('[bgdiff] done')

    # 6. фінальна камера і рендер
    final = P('final')
    flags = ['--no-render'] if '--no-render' in sys.argv else []
    if arg('--range'): flags += ['--range', arg('--range')]
    rendered = os.path.exists(os.path.join(final, 'out_follow.mp4')) or '--no-render' in sys.argv
    if not done(5, os.path.join(final, 'metrics.json')) or not rendered:
        print('[final]', flush=True)
        run([PY, S('follow.py'), video, det, final, '--balls', P('balls.jsonl')] + flags, log=P('final.log')); ran(5)
    else:
        print('[final] done')

    # 7. перевірки: чекліст голів і contact sheet точності
    print('[checks]', flush=True)
    m = json.load(open(os.path.join(final, 'metrics.json')))
    print('  ' + ', '.join(f'{k} {m[k]}' for k in ('ball_found_share', 'ball_in_crop_share', 'players_in_crop_share', 'goal_mode_share') if k in m))
    if checklist:
        run([PY, S('check_goals.py'), os.path.join(final, 'camera_path.npz'), os.path.abspath(checklist)])
    if not done(6, os.path.join(final, 'ball_sheet.jpg')):
        run([PY, S('ball_sheet.py'), video, os.path.join(final, 'ball_track.json'), os.path.join(final, 'ball_sheet.jpg'), '24'])

    # 8. хайлайти
    if '--highlights' in sys.argv and os.path.exists(os.path.join(final, 'out_follow.mp4')):
        print('[highlights]', flush=True)
        run([PY, S('highlights.py'), final, P('highlights')] + (['--checklist', os.path.abspath(checklist)] if checklist else []))

    print(f'pipeline done in {(time.time() - t_all) / 60:.1f} min → {final}')


if __name__ == '__main__':
    main()
