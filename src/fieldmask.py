"""Маска поля: зелена трава, найбільша зв'язна область, опукла оболонка."""
import cv2, numpy as np
def field_mask(src, n=7):
    cap = cv2.VideoCapture(src); N = int(cap.get(7)); fr = []
    for k in range(n):
        cap.set(1, int(N * (k + 0.5) / n)); ok, im = cap.read(); fr.append(im)
    med = np.median(np.stack(fr), axis=0).astype(np.uint8)
    hsv = cv2.cvtColor(med, cv2.COLOR_BGR2HSV)
    g = cv2.inRange(hsv, (35, 50, 40), (90, 255, 255))
    g = cv2.morphologyEx(g, cv2.MORPH_CLOSE, np.ones((25, 25), np.uint8))
    n_, lab, st, _ = cv2.connectedComponentsWithStats(g)
    big = 1 + np.argmax(st[1:, cv2.CC_STAT_AREA])
    comp = (lab == big).astype(np.uint8)
    cnts, _ = cv2.findContours(comp, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
    m = np.zeros_like(comp); cv2.drawContours(m, [max(cnts, key=cv2.contourArea)], -1, 1, -1)  # заповнити дірки
    return m, med
if __name__ == '__main__':
    import sys
    m, med = field_mask(sys.argv[1])
    vis = med.copy(); vis[m == 0] = (vis[m == 0] * 0.3).astype(np.uint8)
    cv2.imwrite('fieldmask.jpg', cv2.resize(vis, (2048, 540)))
    np.save('fieldmask.npy', m)
