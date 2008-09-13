package CacheSmart;

# Will Pierce, (c) 2008, released under GPLv3.
# - Note this is still in early alpha development.
#
# DISCLAIMER
#  Please do not use this code without accepting that it is provided
#  AS IS, and is not necessarily fit for any purpose.
#
# That said, this code is going to evolve over the next few weeks into
# something pretty handy.  Or so I intend, and hope.
#

use strict;
use vars qw (@ISA @EXPORT_OK $VERSION);
use Exporter;
use Time::HiRes;
@ISA = qw( Exporter );
@EXPORT_OK = qw(VERSION);
$VERSION = "1.00";

#
# Class to implement a caching object with fully instrumented metrics
# and multiple strategies for cache management.
#
# The basic idea is that we cache references to objects (which will keep them
# around because the GC won't free them while we hold their reference)
# And then there are insert(), get() and delete() operations
#
# Actually, this could even implement the Tie interface... Well, maybe later.
#
# Expected API:
#
# CacheSmart->new ( 'name'        => "NAME",
#                   ''            =>  ,
#                   ''            =>  ,
#                   ''            =>  ,
#                   ''            =>  ,
#                   ''            =>  ,
#                   ''            =>  ,
#
#
# obj->set ( NAME, VALUE [, SIZE [, TIMECOST] ] )  # does not do deep copy
#   inserts, or updates a cache entry, with an optional SIZE and optional SIZE and TIMECOST
#
# obj->get ( NAME )
#   returns the reference to the entry named 'NAME'
#
# obj->delete ( NAME )
#
# obj->stats()
#   returns hashref with stats represented as key/value pairs
#
# obj->delete_all()
#   removes all objects, but leaves stats unchanged
#
# obj->clear_stats()
#   resets statistics to zero, except for current cache contents
#
# obj->delete_and_clear()
#   a convenience function, equivalent to:
#   obj->delete_all()
#   obj->clear_stats()
#
#

# Class statics
# Fields:     ValueRef, Hits, InsertTime, LastAccess, PreFetchedFlag, Size,  Timecost
my (
    $ENTRY_VALREF,   $ENTRY_HITS,    $ENTRY_INSERT_TIME, $ENTRY_LAST_ACCESS,
    $ENTRY_CONTEXT,  $ENTRY_RES_REF
   ) = (0, 1, 2, 3, 4, 5);

sub new {
  my ($proto, %args) = @_;
  my $class = ref( $proto ) || $proto;
  my %self;
  my %stats;
  my %cache;
  my $bad_constructor = 0;

  my @args_required = ( 'name' );
  my @args_optional = ( 'expire_policy', 'max_size_entries', 'max_size_bytes',
			'policy_lru:max_age', 'policy_lru:check_interval',
			'time_func'
		      );

  # process REQUIRED arguments, set the bad_constructor flag if we missed any and warn()
  foreach my $a ( @args_required ) {
    if (! defined ( $args{$a}) ) {
      warn "CacheSmart: FATAL Constructor error, missing required parameter: $a\n";
      $bad_constructor=1;
    } else {
      $self{$a} = delete ($args{$a}); # assign and delete to clear out args
    }
  }

  # process OPTIONAL arguments
  foreach my $a ( @args_required ) {
    if (defined ( $args{$a}) ) {
      $self{$a} = delete ($args{$a}); # assign and delete to clear out args
    }
  }

  # Set defaults if optionals weren't specified
  my $time_func;
  if (! defined ($time_func = $self{'time_func'})) {
    $time_func = \&Time::HiRes::time;
    $self{'time_func'} = $time_func;
  }

  # handle UNKNOWN arguments
  my @unk_list = sort keys %args;
  if (scalar (@unk_list) > 0) {
    warn "CacheSmart: UNKNOWN constructor arguments (typos?): " . join (", ", @unk_list);
  }

  if ($bad_constructor) {
    warn "FATAL error(s), aborting object construction.\n";
    return (undef);
  }

  # set up initial stats
  $stats{'create_time'} = &$time_func();
  $stats{'current:elements/ALL'} = 0;

  # set up per-object local storage
  $self{'cache'} = \%cache; # actual cache
  $self{'stats'} = \%stats;

  # and set up the final returned object
  my $this = \%self;
  bless ($this, $class);
  return ($this);
}

sub set {
  my $self  = shift;
  my %res   = @_;

  my $name     = delete ($res{'key'});
  my $valref   = delete ($res{'value'});
  my $context  = delete ($res{'context'});

  my $statref  = $self->{'stats'};

  if (! defined ($name)) {
    # error, might as well track it!
    $statref->{'error:set_is_missing_key_entry'}++;
    return (undef);
  }

  my $curtime = $self->_get_time();

  # specific named resources
  my $size = 1;
  if (! defined ($res{'size'})) {
    if (!ref($valref)) {
      # this is a scalar, so size is length() of the string
      my $size = length($valref);
      $res{'size'} = $size;
    }
  }

  # Fields:     ValueRef, Hits, InsertTime, LastAccess, Context Tag, Resource Hashref
  my $entry = [ $valref,  0,    $curtime,   undef,      $context,    \%res];

  my $cacheref = $self->{'cache'};
  my $overwrite = 0;

  # detect cache overwrites
  if (defined (my $old_entry = $cacheref->{$name})) {
    # won't this throw off the stats? TODO: test degenerate case of 90% overwrites and check stats
    # why would stats be wrong? because I need to update stats to subtract the overwritten entry's resources
    # before I add the new element's resources
    $statref->{'counter:insert_overwrite/ALL'}++;
    if (defined ($context)) {
      $statref->{"counter:insert_overwrite/$context"}++;
    }

    my $old_valref = $old_entry->[$ENTRY_VALREF];
    if ($old_valref == $valref) { # compares REFERENCES, not CONTENTS unless values are NUMERIC! IMPT DISTINCTION!
      # just increment a counter, don't actually change behavior
###      print STDERR "debug: insert overwrite is a dupe for \"$name\" Same? Vals: $old_valref == \"$valref\"\n";
      $statref->{'counter:insert_duplicate/ALL'}++;
      if (defined($context)) {
	$statref->{"counter:insert_duplicate/$context"}++;
      }
    }
    # not a duplicate k=v
    my $e_context = $old_entry->[$ENTRY_CONTEXT];
###      print STDERR "debug: in set() with overwrite for key \"$name\", decrementing current:elements/$e_context\n";
    if (defined ($e_context)) {
      $statref->{"current:elements/$e_context"}--;
    }
    my $old_res = $old_entry->[$ENTRY_RES_REF];
    while (my ($k,$v) = each %{ $old_res }) {
###	print STDERR "debug: OLD RES: $k/$e_context = $v, for \"$name\" (subtracting it)\n";
      if (defined ($e_context)) {
	$statref->{"res_current:$k/$e_context"} -= $v;
      }
      $statref->{"res_current:$k/ALL"} -= $v;
    }
  }

  $statref->{'current:elements/ALL'}++;
  if (defined ($context)) {
    $statref->{"current:elements/$context"}++;
  }

  # Actual cache-insert:
  $cacheref->{$name} = $entry;
  $statref->{'counter:insert/ALL'}++;
  if (defined ($context)) {
    $statref->{"counter:insert/$context"}++;
  }

  # ok, these are resources, I must process them generically
  while (my ($k,$v) = each (%res)) {
    #print "updated resource totals/current as $k=$v\n";
    $statref->{"res_current:$k/ALL"}   += $v;
    $statref->{"res_total_set:$k/ALL"} += $v;
    if (defined ($context)) {
      $statref->{"res_current:$k/$context"}   += $v;
      $statref->{"res_total_set:$k/$context"} += $v;
    }
    if ($overwrite) { # is this meaningful?
      $statref->{"res_total_set_overwrite:$k/ALL"} += $v;
      if (defined($context)) {
	$statref->{"res_total_set_overwrite:$k/$context"} += $v;
      }
    }
  }
  return (1);
}

sub set_key {
  my ($self, $k, $v) = @_;
  return ($self->set(
		     'key' => $k,
		     'value' => $v
#		     'context' => 'set_key'
		    )
	 );
}

sub get_key {
  my ($self, $k, $v) = @_;
  return ($self->get(
		     'key' => $k
#		     'context' => 'get_key'
		    )
	 );
}


sub get {
  my $self = shift;
  my %res  = @_;

  my $name = delete ($res{'key'});
  my $context = delete ($res{'context'});

  my $statref = $self->{'stats'};
  $statref->{'counter:get/ALL'}++;
  if (defined ($context)) {
    $statref->{"counter:get/$context"}++;
  }

  my $curtime = $self->_get_time();

  my $entry = $self->{'cache'}->{$name};
  if (! defined ($entry)) {
    $statref->{'counter:get_miss/ALL'}++;
    if (defined($context)) {
      $statref->{"counter:get_miss/$context"}++;
    }
    return (undef);
  }

  # update cache and per-entry stats
  $statref->{'counter:get_hit/ALL'}++;
  if (defined($context)) {
    $statref->{"counter:get_hit/$context"}++;
  }
  $entry->[$ENTRY_LAST_ACCESS]=$curtime;
  my $this_hit = ++$entry->[$ENTRY_HITS];

  # Get resource hashref and update totals
  my $res = $entry->[$ENTRY_RES_REF];
  while (my ($k,$v) = each (%{ $res })) {
    #print "Accessed \"$name\" in context $context, resource $k=$v, for $this_hit time, at TIME: $curtime\n"; # debug
    $statref->{"res_total:res_hit:$k/ALL"} += $v;
    if (defined($context)) {
      $statref->{"res_total:res_hit:$k/$context"} += $v;
    }
  }

  my $age = $curtime - $entry->[$ENTRY_INSERT_TIME];
  $statref->{'total:hit_age/ALL'} += $age;
  if (defined ($context)) {
    $statref->{"total:hit_age/$context"} += $age;
  }

  # return REFERENCE to contents of cache
  return ($entry->[$ENTRY_VALREF]);
}

# wrapper function
sub get_key {
  my ($self, $k) = @_;
  return ($self->get('key' => $k,
		     'context' => 'get_key'));
}

sub delete {
  my $self = shift;
  my %res = @_;

  my $name    = delete ($res{'key'});
  my $context = delete ($res{'context'});

  my $statref  = $self->{'stats'};
  my $cacheref = $self->{'cache'};

  my $curtime = $self->_get_time();

  $statref->{'counter:delete/ALL'}++;
  if (defined($context)) {
    $statref->{"counter:delete/$context"}++;
  }

  # actual deletion from cache
  my $entry;
  if (! defined ($entry = delete($cacheref->{$name}))) {
    $statref->{'counter:delete_noentry/ALL'}++;
    if (defined($context)) {
      $statref->{"counter:delete_noentry/$context"}++;
    }
    return (undef);
  }

  $statref->{'current:elements/ALL'}--;
  my $e_context = $entry->[$ENTRY_CONTEXT];
  if (defined ($e_context)) {
    $statref->{"current:elements/$e_context"}--;
  }

  # update resources (size and timecost, etc) totals for explicitly deleted objects
  my $res = $entry->[$ENTRY_RES_REF];
  while (my ($k,$v) = each (%{ $res })) {
    $statref->{"res_total:deleted:$k/ALL"} += $v;
    $statref->{"res_current:$k/ALL"} -= $v;
    if (defined ($context)) {
      $statref->{"res_total:deleted:$k/$context"} += $v;
    }
    if (defined ($e_context)) {
      $statref->{"res_current:$k/$e_context"} -= $v;
    }
  }

  my $e_hits = $entry->[$ENTRY_HITS];
  if (defined ($e_hits)) {
    $statref->{'total:deleted_sum_hits/ALL'}     += $e_hits;
    if (defined ($context)) {
      $statref->{"total:deleted_sum_hits/$context"}     += $e_hits;
    }
    # and per-resource sum!
    while (my ($k,$v) = each (%{ $res })) {
      $statref->{"res_total:deleted_sum:$k/ALL"}     += $e_hits * $v;
      if (defined ($context)) {
	$statref->{"res_total:deleted_sum:$k/$context"}     += $e_hits * $v;	
      }
    }
  }

  my $e_add_time = $entry->[$ENTRY_INSERT_TIME];
  if (defined($e_add_time)) {
    my $age = $curtime - $e_add_time;
    $statref->{'total:deleted_age/ALL'} += $age;
    if (defined ($context)) {
      $statref->{"total:deleted_age/$context"} += $age;
    }
  }

  undef($entry); # clear refcount explicitly... not really needed.
}

sub stats {
  my $self = shift;
  return ($self->{'stats'});
}

sub delete_all {
  my $self = shift;
  my %res = @_;
  my %cache;
  # update counters
  my $context = delete ($res{'context'});

  my $statref = $self->{'stats'};
  my $zap_total = scalar ( @{ $self->{'cache'} } );
  $statref->{'counter:delete/ALL'} += $zap_total;
  if (defined ($context)) {
    $statref->{"counter:delete/$context"} += $zap_total;
  }
  # only bit of looping needed... just to add up deleted sizes and timecost, it's cheap!
  my %res_k;
  foreach my $i (@{ $self->{'cache'} }) {
    # deal w/ resources here
    my $res = $i->[$ENTRY_RES_REF];
    while (my ($k,$v) = each %{ $res }) {
      $res_k{$k}++;
      $statref->{"res_total:deleted:$k/ALL"} += $v;
      if (defined ($context)) {
	$statref->{"res_total:deleted:$k/$context"} += $v;
      }
    }
  }
  # deal w/ resources per-element
  $statref->{'current:elements/ALL'}        = 0;
  $self->{'cache'} = \%cache; #blast entire contents
  foreach my $k (keys %res_k) {
    delete ($statref->{"total:$k/ALL"});
    if (defined ($context)) {
      delete ($statref->{"total:$k/$context"});
    }
  }
}

# be careful with this call... it can leave your cache in an inconsistent state!
sub clear_stats {
  my $self = shift;
  $self->_reset_stats();
}

# this one is safe to call...
sub delete_and_clear {
  my $self = shift;
  $self->delete_all();
  $self->clear_stats();
}

# -------------------------------------------------------------------------------
# internal helper functions below...  never call these directly.
sub _reset_stats {
  my ($self) = @_;
  my %stats;
  $stats{'create_time'} = $self->{'stats'}->{'create_time'};
  $self->{'stats'} = \%stats;
}

sub _get_time {
  my ($self) = @_;
  my $time_func = $self->{'time_func'};
  return ( &$time_func() );
}



package CachePoller;

sub new {
  my ($proto, %args) = @_;
  my $class = ref( $proto ) || $proto;
  my %self;


  # and set up the final returned object
  my $this = \%self;
  bless ($this, $class);
  return ($this);
}


1;

