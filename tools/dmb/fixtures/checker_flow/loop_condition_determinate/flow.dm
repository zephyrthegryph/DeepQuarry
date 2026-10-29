/proc/loops(a)
    for(var/i=0;1;i++)
        a=1
    for(var/j=0;0;j++)
        a=2
    for(var/k=0;a;k++)
        a=3
    for(var/m=0;1 || a;m++)
        a=4
    while(1)
        a=5
    do
        a=6
    while(1)
/proc/skipped(a)
    return
    for(var/i=0;1;i++)
        a=1
