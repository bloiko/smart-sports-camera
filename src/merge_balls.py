"""Об'єднати детекції м'яча кількох моделей (кожна зі своїм порогом) в один файл для follow.py --balls.
Використання: python src/merge_balls.py out.jsonl base.jsonl:0.25 ball_v02.jsonl:0.4
Моделі доповнюють одна одну: на матчі 2 база дала 55%, v0.2 — менше, а разом 66% відліків з м'ячем.
"""
import json, sys
out, srcs = sys.argv[1], [(p.split(':')[0], float(p.split(':')[1])) for p in sys.argv[2:]]
data = [({json.loads(l)['frame']: json.loads(l)['balls'] for l in open(p)}, th) for p, th in srcs]
frames = sorted(set().union(*[d.keys() for d, _ in data]))
with open(out, 'w') as f:
    for fr in frames:
        bs = [b[:4] + [1.0] for d, th in data for b in d.get(fr, []) if b[4] >= th]
        f.write(json.dumps({'frame': fr, 'balls': bs}) + '\n')
