#!/usr/bin/python
#
# cachesmart, J. Will Pierce
# trivial edit
#
# this file includes CacheSmart class, which implements the instrumented cache
# with a similar API to the perl implementation
from __future__ import division
import time
import UserDict

import traceback

class CacheContext(object):
    def __init__(self, cache, context):
        self.cache = cache
        self.context = context

    def __enter__(self):
        cache = self.cache
        print 'setting context:',self.context
        cache.push_context(self.context)

    def __exit__(self, exc_type, exc_val, exc_tb):
        cache = self.cache
        last_context = cache.pop_context()
        print 'removed context:', last_context, '  (exc_type, exc_val, exc_tb)=',exc_type, exc_val, exc_tb


class CachePolicy(object):
    (MAX_AGE, LRU, MAX_EVIL) = range(3)
    def __init__(self, policy):
        self.policy = policy
        self.max_age = None

    def __str__(self):
        names = {'0':'MAX_AGE', '1':'LRU', '2':'MAX_EVIL'}
        myname = names[str(self.policy)]
        return ('CachePolicy(CachePolicy.%s)' % (myname))

class Entry(object):
    '''Class to contain a cache entry'''
    def __init__(self, k, v, insert_time=None, context=None, resource=None):
        self.k = k
        self.v = v
        self.insert_time = insert_time
        self.context = context
        self.resource = resource
        self.count_gets = 0
        self.count_sets = 1
        self.last_get = None
        self.last_set = insert_time

    def __repr__(self):
        age = time.time() - self.insert_time
        str = "Entry object: ( %s,  %s,  context=%s, count_gets=%d,  count_sets=%d,  age=%fs )" % (repr(self.k), repr(self.v), repr(self.context), self.count_gets, self.count_sets, age)
        return (str)

class CacheSmart(UserDict.DictMixin):
    # these may be a bad idea in python, they were mostly an efficiency thing in perl
    (ENTRY_VALREF, ENTRY_HITS, ENTRY_INSERT_TIME, ENTRY_LAST_ACCESS, ENTRY_CONTEXT, ENTRY_RES_REF) = range(6)

    def __init__(self, name, contents=None,
        max_size_entries=None, max_size_bytes=None,
        expire_policy=None, default_context=None,
        time_func=time.time):
        print "New CacheSmart instance named:",name
        self.name = name
        #print "ENTRY things: ", self.ENTRY_VALREF, self.ENTRY_HITS, self.ENTRY_INSERT_TIME, self.ENTRY_LAST_ACCESS, self.ENTRY_CONTEXT, self.ENTRY_RES_REF
        counter_dict = { 'insert_overwrite':0, 'get_default_val':0, 'gets':0, 'tests':0, 'tests_true':0, 'tests_false':0,
                        'deletes':0, 'deletes_fail':0, 'set_missing_key':0}
        self.context_stack = []
        self.default_context = default_context
        self.ctx_stats = dict(ALL=dict(current_elements=0)) # default includes an 'ALL' context
        self.stats = counter_dict
        self.data = dict()
        # size/behavior params
        self.max_size_entries = max_size_entries
        self.max_size_bytes = max_size_bytes
        self.expire_policy = expire_policy
        # tracking params
        self.create_time = time_func()
        self.time_func = time_func

    def __setitem__(self, k, v):
        if k is None:
            self.stats['set_missing_key'] += 1
            raise KeyError('No key name specified.')
        print "Tried to do a SETITEM for \'%s\'." % (k)
        if len(self.context_stack):
            print 'current context is:', self.context_stack[-1]
        curtime = self.time_func()
        entry = Entry(k, v, insert_time=curtime, context=self._current_context(), resource=None)
        if k in self.data:
            print 'about to clobber existing key %s' % k
            entry = self.data[k]
            entry.v = v
        else:
            print 'setting dict with key \'%s\' and val \'%s\' hah' % (k, v)
            self.data[k]=entry

    def __getitem__(self, k):
        print "Tried to do a GETITEM for \'%s\'." % (k)
        entry = self.data[k]
        entry.count_gets += 1
        entry.last_get = self.time_func()
        #print 'Callstack:'
        #traceback.print_stack()
        print 'Returning item:', k, 'val:', entry.v
        # must print out call stack
        return (entry.v)

    def _current_context(self):
        if len(self.context_stack) == 0:
            return self.default_context # defaults to None
        return (self.context_stack[-1])

    # Manual exposure of the context stack
    def push_context(self, context):
        if context == 'ALL':
            raise ValueError('Cannot use a context named "ALL" due to conflict with top level summary context.')
        self.context_stack.append(context)

    def pop_context(self):
        last_context = self.context_stack.pop()
        return (last_context)

    # does this work right? it should hit the __getitem__() for each key...
    def __iter__(self):
        return self.data.__iter__()

    def __delitem__(self, k):
        self.stats['deletes'] += 1
        if k not in self.data:
            self.stats['deletes_fail'] += 1
        del self.data[k]

    def __contains__(self, k):
        is_present = k in self.data
        self.stats['tests'] += 1
        if is_present:
            self.stats['tests_true'] += 1
        else:
            self.stats['tests_false'] += 1
        return is_present

    def __len__(self):
        return len(self.data)

    def keys(self):
        print 'keys() called.  INEFFICIENT! Remove this somehow.'
        keylist = [k for k in self.data]
        return (keylist)

    def set(self, k, v, context=None, resource=None):
        if k is None:
            #self.stats['error']
            raise KeyError('No key name specified.')
        curtime = self.time_func()
        entry = Entry(k, v, curtime, context, resource)
        self.data[k]=entry

    def get(self, k, default=None, context=None, resource=None):
        print 'IMPLEMENTED MY OWN get() method'
        self.stats['gets'] += 1
        if k in self.data:
            return (self.data[k])
        print 'Not found! Returning default...'
        self.stats['get_default_val'] += 1
        return (default)

    def update(self, dict=None, **kwargs):
        raise NotImplementedError('CacheSmart does not yet support update() for bulk cache updates.  Most humble apologies.')

    def __str__(self):
        clist = []
        for (k,v) in self.data.iteritems():
            clist.append('%s=%s' % (k,repr(v.v)) )
        contents = ', '.join (clist)
        params = [ 'name=\'%s\'' % (self.name),  'contents=dict(%s)' % contents ]
        for c in ('max_size_entries', 'max_size_bytes', 'expire_policy'):
            v = getattr(self, c)
            if v is not None:
                params.append('%s=%s' % (c, v))
        str = 'CacheSmart(%s)' % (', '.join(params))
        str += '\n #   cache: ' + repr(self.data)
        return (str)


if __name__ == '__main__':
    print 'start of program...'
    exp = CachePolicy(CachePolicy.LRU)
    cs = CacheSmart('mycache', expire_policy=exp)
    print '\n1. setting first item...'
    cs['first'] = 'abc 123'
    time.sleep(0.014)
    cs['second'] = 234.0
    time.sleep(0.029)
    print '\n2. printing out value of "first" retrieval:\n'
    print 'first is: ',cs.get('first3', 2245)

    print '\n3. printing out entire cache object...'
    print cs
    print '\n4. about to access an item...'
    x=cs['first']

    print '\n5. Stats:'
    print cs

    print '\n\nTrying to get an arbitrary key:'
    (k, v) = cs.popitem()
    print 'Got k=',k,'  v=',v

    print 'keys in cache dict:',cs.keys()
    time.sleep(0.15)

    ret = 'first' in cs
    print 'Is "first" in cache? Answer:', ret

    with CacheContext(cs, 'read-user'):
        cs['three'] = 'THREE(read user)'
        cs['four'] = 'FOUR(read user)'
        with CacheContext(cs, 'write-user'):
            cs['five'] = 'FIVE(write-user)'

    cs.push_context('manual-ctx')
    cs['six'] = 'SIX(manual)'
    cs['seven'] = 'SEVEN(manual)'
    cs.pop_context()

    print '\n\nITERATING through entire cache object....'
    for (k,v) in cs.iteritems():
        print '%s = %s' % (k, v)

    print '\n and printing out stats now:'
    print cs.stats

    print '\n current cache contents:'
    print cs.data
    print 'LEN:',len(cs)
    print 'and userdict...'
    x = UserDict.DictMixin()
    print dir(x)
