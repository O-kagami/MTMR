-- Avoid starting Spotify unexpectedly; this control only operates Spotify.
if application id "com.spotify.client" is running then
    tell application id "com.spotify.client" to playpause
end if
