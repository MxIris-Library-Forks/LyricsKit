//
//  NetEase.swift
//  LyricsX - https://github.com/ddddxxx/LyricsX
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import LyricsCore
import CXShim
import CXExtensions
import Regex

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private let netEaseSearchBaseURLString = "http://music.163.com/api/search/pc?"
private let netEaseLyricsBaseURLString = "http://music.163.com/api/song/lyric?"

extension LyricsProviders {
    public final class NetEase {
        public init() {}
    }
}

extension LyricsProviders.NetEase: _LyricsProvider {
    
    public struct LyricsToken {
        let value: NetEaseResponseSearchResult.Result.Song
    }
    
    public static let service: LyricsProviders.Service = .netease
    
    public func lyricsSearchPublisher(request: LyricsSearchRequest) -> AnyPublisher<LyricsToken, Never> {
        let parameter: [String: Any] = [
            "s": request.searchTerm.description,
            "offset": 0,
            "limit": 10,
            "type": 1,
            ]
        let url = URL(string: netEaseSearchBaseURLString + parameter.stringFromHttpParameters)!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("http://music.163.com/", forHTTPHeaderField: "Referer")
        
        return sharedURLSession.cx.dataTaskPublisher(for: req)
            .map { $0.data }
            .decode(type: NetEaseResponseSearchResult.self, decoder: JSONDecoder().cx)
            .map(\.songs)
            .replaceError(with: [])
            .flatMap(Publishers.Sequence.init)
            .map(LyricsToken.init)
            .eraseToAnyPublisher()
    }
    
    public func lyricsFetchPublisher(token: LyricsToken) -> AnyPublisher<Lyrics, Never> {
        let parameter: [String: Any] = [
            "id": token.value.id,
            "lv": 1,
            "kv": 1,
            "tv": -1,
        ]
        let url = URL(string: netEaseLyricsBaseURLString + parameter.stringFromHttpParameters)!
        return sharedURLSession.cx.dataTaskPublisher(for: url)
            .map { $0.data }
            .decode(type: NetEaseResponseSingleLyrics.self, decoder: JSONDecoder().cx)
            .compactMap {
                let lyrics: Lyrics
                let transLrc = ($0.tlyric?.fixedLyric).flatMap(Lyrics.init)
                if let kLrc = ($0.klyric?.fixedLyric).flatMap(Lyrics.init(netEaseKLyricContent:)) {
                    transLrc.map(kLrc.forceMerge)
                    lyrics = kLrc
                } else if let lrc = ($0.lrc?.fixedLyric).flatMap(Lyrics.init) {
                    transLrc.map(lrc.merge)
                    lyrics = lrc
                } else {
                    return nil
                }
                
                // FIXME: merge inline time tags back to lyrics
                // if let taggedLrc = (model.klyric?.lyric).flatMap(Lyrics.init(netEaseKLyricContent:))
                
                lyrics.idTags[.title]   = token.value.name
                lyrics.idTags[.artist]  = token.value.artists.first?.name
                lyrics.idTags[.album]   = token.value.album.name
                lyrics.idTags[.lrcBy]   = $0.lyricUser?.nickname
                
                lyrics.length = Double(token.value.duration) / 1000
                lyrics.metadata.artworkURL = token.value.album.picUrl
                lyrics.metadata.serviceToken = "\(token.value.id)"
                
                return lyrics
            }.ignoreError()
            .eraseToAnyPublisher()
    }
}

private let netEaseTimeTagFixer = try! Regex(#"(\[\d+:\d+):(\d+\])"#)

private extension NetEaseResponseSingleLyrics.Lyric {
    var fixedLyric: String? {
        return lyric?.replacingMatches(of: netEaseTimeTagFixer, with: "$1.$2")
    }
}
