/proc/keyword_calls(datum/keyword_alpha/alpha,datum/keyword_zeta/zeta)
    zeta.task(first=1,second=2)
    alpha.work(beta=1,alpha=alpha.work(alpha=2,beta=3))
    alpha.work("alpha"=3)
