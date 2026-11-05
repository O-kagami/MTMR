-- A space keeps the MTMR item visible; its image represents Spotify's state.
try
    if application id "com.spotify.client" is not running then return {" ", "unavailable"}
    tell application id "com.spotify.client"
        if player state is playing then return {" ", "pause"}
        return {" ", "play"}
    end tell
on error
    return {" ", "unavailable"}
end try
