property graphDir : (POSIX path of (path to library folder from user domain)) & "Application Support/MTMR/CPU-Memory/"
on run
    try
        set active to read POSIX file (graphDir & "mode.txt") as «class utf8»
        if active starts with "memory" then return {" ", "memory"}
    end try
    return {" ", "cpu"}
end run
