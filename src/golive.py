"""Go live: одна команда — вхід у Google, створення трансляції на YouTube, стрім live-камери з Mac.

Імітує, що робитиме застосунок: користувач бачить лише вікно «Дозволити доступ до YouTube» (перший раз)
і посилання на трансляцію. Ключі стріму не показуються і не зберігаються у репозиторії.

Використання:
  python src/golive.py VIDEO CAMERA_PATH.npz [--title "Test match"] [--from 60] [--privacy unlisted]
  VIDEO — записане відео (імітація камери), CAMERA_PATH.npz — траєкторія live-камери (live_sim.py, буфер 2 с).

Потрібно один раз: secrets/client_secret.json з Google Cloud (OAuth client, тип Desktop, YouTube Data API v3
увімкнено). Токен після входу зберігається в secrets/token.json. Папка secrets/ у .gitignore.
"""
import json, os, subprocess, sys, time
import numpy as np, cv2

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SECRETS = os.path.join(ROOT, 'secrets')
SCOPES = ['https://www.googleapis.com/auth/youtube.force-ssl']


def arg(name, default=None):
    return sys.argv[sys.argv.index(name) + 1] if name in sys.argv else default


def youtube():
    from google.oauth2.credentials import Credentials
    from google_auth_oauthlib.flow import InstalledAppFlow
    from google.auth.transport.requests import Request
    from googleapiclient.discovery import build
    tok = os.path.join(SECRETS, 'token.json'); creds = None
    if os.path.exists(tok): creds = Credentials.from_authorized_user_file(tok, SCOPES)
    if not creds or not creds.valid:
        if creds and creds.expired and creds.refresh_token: creds.refresh(Request())
        else:
            cs = os.path.join(SECRETS, 'client_secret.json')
            if not os.path.exists(cs): sys.exit(f'Потрібен {cs} (Google Cloud → OAuth client, Desktop app)')
            creds = InstalledAppFlow.from_client_secrets_file(cs, SCOPES).run_local_server(port=0, prompt='consent')
        os.makedirs(SECRETS, exist_ok=True); open(tok, 'w').write(creds.to_json())
    return build('youtube', 'v3', credentials=creds)


def create_broadcast(yt, title, privacy):
    """Трансляція + стрім, зв'язані між собою. Повертає (broadcast_id, rtmps url, ключ, посилання)."""
    start = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(time.time() + 15))
    b = yt.liveBroadcasts().insert(part='snippet,status,contentDetails', body={
        'snippet': {'title': title, 'scheduledStartTime': start},
        'status': {'privacyStatus': privacy, 'selfDeclaredMadeForKids': False},
        'contentDetails': {'enableAutoStart': True, 'enableAutoStop': True, 'latencyPreference': 'low'}}).execute()
    s = yt.liveStreams().insert(part='snippet,cdn,contentDetails', body={
        'snippet': {'title': title}, 'cdn': {'frameRate': '30fps', 'ingestionType': 'rtmp', 'resolution': '1080p'},
        'contentDetails': {'isReusable': False}}).execute()
    yt.liveBroadcasts().bind(part='id', id=b['id'], streamId=s['id']).execute()
    ing = s['cdn']['ingestionInfo']
    return b['id'], ing['rtmpsIngestionAddress'], ing['streamName'], f"https://youtu.be/{b['id']}"


def stream(video, path, url, key, t0):
    p = np.load(path); X, Y, CW, CH = p['X'], p['Y'], p['CW'], p['CH']
    cap = cv2.VideoCapture(video); fps = cap.get(5); cap.set(cv2.CAP_PROP_POS_FRAMES, int(t0 * fps))
    ff = subprocess.Popen(['ffmpeg', '-v', 'error', '-re', '-f', 'rawvideo', '-pix_fmt', 'bgr24', '-s', '1920x1080', '-r', str(fps), '-i', '-',
                           '-ss', str(t0), '-i', video, '-map', '0:v', '-map', '1:a?',
                           '-c:v', 'h264_videotoolbox', '-b:v', '4500k', '-maxrate', '4500k', '-bufsize', '9000k', '-pix_fmt', 'yuv420p',
                           '-g', str(int(fps * 2)), '-c:a', 'aac', '-b:a', '128k', '-ar', '44100', '-f', 'flv', f'{url}/{key}'], stdin=subprocess.PIPE)
    f = int(t0 * fps); t_start = time.time()
    while f < len(X):
        ok, im = cap.read()
        if not ok: break
        x0, y0 = int(X[f] - CW[f] / 2), int(Y[f] - CH[f] / 2)
        fr = cv2.resize(im[max(y0, 0):y0 + int(CH[f]), max(x0, 0):x0 + int(CW[f])], (1920, 1080), interpolation=cv2.INTER_LINEAR)
        try: ff.stdin.write(fr.tobytes())
        except BrokenPipeError: break
        f += 1
        if f % int(fps * 10) == 0: print(f'  streaming {(f - int(t0 * fps)) / fps:.0f} s, realtime {time.time() - t_start:.0f} s', flush=True)
    ff.stdin.close(); ff.wait()


def main():
    video, path = sys.argv[1], sys.argv[2]
    yt = youtube()
    bid, url, key, link = create_broadcast(yt, arg('--title', 'Smart camera test'), arg('--privacy', 'unlisted'))
    print(f'Трансляція створена: {link}  (відкрий на телефоні; стрім стартує автоматично)', flush=True)
    try:
        stream(video, path, url, key, float(arg('--from', 0)))
    finally:
        try: yt.liveBroadcasts().transition(part='id', id=bid, broadcastStatus='complete').execute()
        except Exception: pass
        print(f'Трансляцію завершено, архів: {link}')


if __name__ == '__main__':
    main()
