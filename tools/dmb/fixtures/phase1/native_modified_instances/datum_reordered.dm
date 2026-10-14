/world
/datum/base
    var/amount=0
    var/other=0
var/global/a=/datum/base{amount=1;other=2}
var/global/b=/datum/base{other=2;amount=1}
var/global/c=/datum/base{amount=1;amount=2}
