#!/usr/bin/python
#
# cachesmart, J. Will Pierce
#
# this file includes CacheSmart class, which implements the instrumented cache
# with a similar API to the perl implementation

class CacheSmart(object):
  # these may be a bad idea in python, they were mostly an efficiency thing in perl
  (ENTRY_VALREF, ENTRY_HITS, ENTRY_INSERT_TIME, ENTRY_LAST_ACCESS, ENTRY_CONTEXT, ENTRY_RES_REF) = range(6)

  def __init__(self):
    print "New instance!"
    print "ENTRY things: ", self.ENTRY_VALREF, self.ENTRY_HITS, self.ENTRY_INSERT_TIME, self.ENTRY_LAST_ACCESS, self.ENTRY_CONTEXT, self.ENTRY_RES_REF
    pass



if __name__ == '__main__':
  cs = CacheSmart()
