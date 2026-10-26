"""Historical diagnostic guard, extracted unchanged for offline regression testing.
Not a production provider or current host admission observation.
"""
def safe(current,initial):
    if current['pressureCode']!=1:return 'memory-pressure'
    if current['availableProxyBytes']<4*1024**3:return 'host-reserve'
    if current['swapUsedBytes']>initial['swapUsedBytes']:return 'swap-growth'
    if current['compressorBytes']-initial['compressorBytes']>512*1024**2:return 'compression-growth'
    return None
