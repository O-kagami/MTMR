property graphDir : (POSIX path of (path to library folder from user domain)) & "Application Support/MTMR/ManagedMedia/v1/CPU-Memory/"
property lastSample : missing value
property lastMode : "cpu"
on run
    try
        set modeText to read POSIX file (graphDir & "mode.txt") as «class utf8»
        if modeText starts with "memory" then
            set lastMode to "memory"
        else
            set lastMode to "cpu"
        end if
        set nowTime to current date
        if lastSample is missing value or (nowTime - lastSample) ≥ 1 then
            do shell script quoted form of (graphDir & "graph") & " " & quoted form of graphDir & " sample"
            set lastSample to nowTime
        end if
        return {" ", lastMode}
    on error
        return {" ", lastMode}
    end try
end run
