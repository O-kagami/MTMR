-- Do not launch Spotify just to skip tracks.
if application id "com.spotify.client" is running then
    tell application id "com.spotify.client" to next track
end if
