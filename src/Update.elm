module Update exposing (update, subscriptions)

import Json.Decode as Decode exposing (..)
import Json.Decode.Extra exposing ((|:), optionalField)
import List.Extra exposing (replaceIf, uniqueBy)
import WebSocket
import Model exposing (..)
import Messages exposing (Msg(..))


websocketURL : String
websocketURL =
    "ws://localhost:4000/ws"



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions model =
    WebSocket.listen websocketURL NewMessage


decodeTorrentFile : Decode.Decoder TorrentFile
decodeTorrentFile =
    succeed TorrentFile
        |: (field "name" string)
        |: (field "length" int)
        |: (field "path" string)
        |: (optionalField "url" string)


decodeTorrentStats : Decode.Decoder TorrentStats
decodeTorrentStats =
    succeed TorrentStats
        |: (field "downloaded" int)
        |: (field "speed" float)
        |: (field "progress" float)


decodeStatus : String -> Decode.Decoder DownloadStatus
decodeStatus status =
    succeed (stringToDownloadStatus status)


stringToDownloadStatus : String -> DownloadStatus
stringToDownloadStatus status =
    case status of
        "download:start" ->
            Started

        "download:progress" ->
            InProgress

        "download:complete" ->
            Complete

        "download:failed" ->
            Failed

        _ ->
            Unknown


torrentDecoder : Decode.Decoder Torrent
torrentDecoder =
    succeed Torrent
        |: (field "name" string)
        |: (field "hash" string)
        |: (field "status" string |> Decode.andThen decodeStatus)
        |: (optionalField "stats" (Decode.field "stats" decodeTorrentStats))
        |: (field "files" (Decode.list decodeTorrentFile))


statusDecoder : Decode.Decoder String
statusDecoder =
    Decode.field "status" Decode.string


nullTorrent : Torrent
nullTorrent =
    Torrent "" "" Unknown Nothing []


decodeTorrent : String -> Torrent
decodeTorrent payload =
    case decodeString torrentDecoder payload of
        Ok torrent ->
            let
                _ =
                    Debug.log "Successfuly parsed torrent payload " torrent
            in
                torrent

        Err error ->
            let
                _ =
                    Debug.log "UnSuccessful parsing of torrent " error
            in
                nullTorrent


dedupeTorrents : List Torrent -> List Torrent
dedupeTorrents torrents =
    uniqueBy (\torrent -> torrent.hash) torrents


updateTorrentProgress : Torrent -> List Torrent -> List Torrent
updateTorrentProgress parsedTorrent modelTorrents =
    replaceIf (\torrent -> torrent.hash == parsedTorrent.hash) parsedTorrent (dedupeTorrents modelTorrents)


update : Msg -> Model -> ( Model, Cmd Msg )
update msg { connectionStatus, currentLink, torrents } =
    case msg of
        Input newInput ->
            ( Model connectionStatus newInput torrents, Cmd.none )

        Send ->
            ( Model connectionStatus "" torrents, WebSocket.send websocketURL currentLink )

        NewMessage str ->
            case str of
                "Connection established" ->
                    ( Model Online currentLink torrents, Cmd.none )

                _ ->
                    let
                        status =
                            Decode.decodeString statusDecoder str

                        _ =
                            Debug.log "Status " status
                    in
                        case status of
                            Ok "download:start" ->
                                ( Model connectionStatus currentLink ((decodeTorrent str) :: (dedupeTorrents torrents)), Cmd.none )

                            Ok "download:progress" ->
                                ( Model connectionStatus currentLink (updateTorrentProgress (decodeTorrent str) torrents), Cmd.none )

                            Ok "download:complete" ->
                                ( Model connectionStatus currentLink (updateTorrentProgress (decodeTorrent str) torrents), Cmd.none )

                            Ok _ ->
                                ( Model connectionStatus currentLink torrents, Cmd.none )

                            Err _ ->
                                ( Model connectionStatus currentLink torrents, Cmd.none )
