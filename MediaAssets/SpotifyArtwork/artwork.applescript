property artworkDir : (POSIX path of (path to library folder from user domain)) & "Application Support/MTMR/ManagedMedia/v1/SpotifyArtwork/"
property lastEnsure : missing value
on run
    try
        set nowTime to current date
        if lastEnsure is missing value or (nowTime - lastEnsure) ≥ 5 then
            set lastEnsure to nowTime
            set alive to false
            try
                do shell script quoted form of (artworkDir & "artwork-worker") & " " & quoted form of artworkDir & " '' --status"
                set alive to true
            end try
            if not alive then
                set initialID to ""
                try
                    if application id "com.spotify.client" is running then
                        tell application id "com.spotify.client"
                            if (player state as text) is not "stopped" then set initialID to id of current track
                        end tell
                    end if
                end try
                do shell script quoted form of (artworkDir & "artwork-worker") & " " & quoted form of artworkDir & " " & quoted form of initialID & " >/dev/null 2>&1 </dev/null &"
            end if
        end if
    end try
    return {" ", "cover"}
end run
