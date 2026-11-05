property graphDir : (POSIX path of (path to library folder from user domain)) & "Application Support/MTMR/ManagedMedia/v1/CPU-Memory/"
do shell script quoted form of (graphDir & "graph") & " " & quoted form of graphDir & " toggle >/dev/null 2>&1 </dev/null &"
