module physical_constants

import ..yt_array: YTQuantity

using PyCall

@pyimport yt.utilities as ytutils

G = YTQuantity(ytutils.physical_constants["G"])
kboltz = YTQuantity(ytutils.physical_constants["kboltz"])
clight = YTQuantity(ytutils.physical_constants["clight"])
me = YTQuantity(ytutils.physical_constants["me"])
mp = YTQuantity(ytutils.physical_constants["mp"])
mh = mp
qp = YTQuantity(ytutils.physical_constants["qp"])
hcgs = YTQuantity(ytutils.physical_constants["hcgs"])
sigma_thompson = YTQuantity(ytutils.physical_constants["sigma_thompson"])
amu_cgs = YTQuantity(ytutils.physical_constants["amu_cgs"])
Na = 1 / amu_cgs

end