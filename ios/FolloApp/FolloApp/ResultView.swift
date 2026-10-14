import SwiftUI
import AVKit

/// Екран 8 «результат»: посилання на архів YouTube, кліпи хайлайтів (16:9 / 9:16), поділитись.
struct ResultView: View {
    let watchURL: String?
    let clips: [HighlightsRunner.Clip]
    let progress: String?
    @State var vertical = false
    @State var playing: URL?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Матч записано").font(.system(size: 26, weight: .heavy, design: .rounded))
            if let w = watchURL {
                HStack { Text(w).font(.footnote).lineLimit(1); Spacer(); ShareLink(item: URL(string: w)!) { Image(systemName: "square.and.arrow.up") } }
                    .padding(10).background(.white.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 10))
            }
            if let p = progress { HStack { ProgressView(); Text(p).font(.footnote).foregroundStyle(.secondary) } }
            if !clips.isEmpty {
                Picker("", selection: $vertical) { Text("16:9").tag(false); Text("9:16 Reels").tag(true) }.pickerStyle(.segmented)
                List(clips.indices, id: \.self) { i in
                    let c = clips[i]; let url = vertical ? c.vertical : c.file
                    HStack {
                        Image(systemName: c.kind == "goal" ? "soccerball.inverse" : "flag").foregroundStyle(c.kind == "goal" ? .red : .secondary)
                        VStack(alignment: .leading) { Text(c.label).font(.headline); Text("\(Int(c.end - c.start)) с").font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        Button { playing = url } label: { Image(systemName: "play.circle") }
                        ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
                    }
                }.listStyle(.plain)
            } else if progress == nil { Text("Небезпечних моментів не знайдено").font(.footnote).foregroundStyle(.secondary) }
            Spacer()
        }
        .padding(16)
        .sheet(item: $playing) { url in VideoPlayer(player: AVPlayer(url: url)).ignoresSafeArea() }
    }
}

extension URL: Identifiable { public var id: String { absoluteString } }
