#!/usr/bin/perl
BEGIN {
  push (@INC, ".");
}
use CacheSmart;
use Time::HiRes qw (sleep time);

$|=1;
print "\n" x 5;
print "-" x 80 . "\n";

my $MAX_KEYS = 10000;

my $obj = CacheSmart->new (
			   'name' => "My Test Cache"
			  );

my $result;
srand (143);
my $i = 0;
my $c_i = 1;
$obj->set ('key' => 'key1',
	   'value' => 0,
	   'context' => 'pre-init'
	  );
while ($i++ <= $MAX_KEYS) {
  my $k = "key" . int(rand($i));
  my $v = rand($i);
  #print "about to set $k=$v\n";
  $obj->set ('key'      => $k,
	     'value'    => int($i/10),
	     'context'  => "initialization$c_i" ,
	     # resource costs
	     'size'     => length($v),
	     'timecost' => $v
	    );
  if ($i % 3700 == 0) {
    $c_i++;
  }
  #sleep ($r/100000);
}

$i=0;
while ($i++ <=  ($MAX_KEYS/3) ) { # read at this ratio of writes
  my $r = int(rand( 2 * $MAX_KEYS)); # aim at 50% hit rate
  $result = $obj->get(
		      'key' => "key$r",
		      'context' => 'post-test'
		     );
}

$result = $obj->get('key' => "key1",
		   'context' => 'post-test');
#print "from cache, result of \"key1\" is: $result\n";
sleep(0.1);
$obj->delete (
	      'key' => "key1",
	      'context' => 'post-test'
	     );
$result = $obj->get( 'key' => "key1",
		     'context' => 'post-test' );
# hot entries:
foreach my $loop1 (0 .. $MAX_KEYS/100) {
  foreach my $loop2 (0 .. 100 ) {
    $result = $obj->get(
			'key' => "key$loop2",
			'context' => 'post-test'
		       );
  }
}

$obj->delete (
	      'key' => "key1",
	      'context' => 'read-test'
	     );
$obj->set ('key'   => "key1",
	   'value' => "val1",
	   'size'  => 4,
	   'timecost' => 0.5,
	   'context'  => 'post-test'
	  );
$obj->delete (
	      'key'   => "key2",
	      'context' => 'post-test'
	     );

my $s = $obj->stats();
foreach my $k (sort keys %{ $s }) {
  printf ("  %-40s = %s\n", $k, $s->{$k});
}

# then inspect specifically the individual cache entry's resources, sum them up and compare
my %sums;
while (my ($k, $v) = each (%{ $obj->{'cache'} } ) ) {
  my $context = $v->[4];
  my $res     = $v->[5];
  foreach my $res_k (keys %{ $res }) {
    $sums{$res_k}->{$context} += $res->{$res_k};
  }
}
foreach my $r (sort keys %sums) {
  my $all = 0;
  foreach my $c (sort keys %{ $sums{$r} }) {
    print "> res_current:$r/$c = " . $sums{$r}->{$c} . "\n";
    $all+= $sums{$r}->{$c};
  }
  print "> res_current:$r/ALL = $all\n";
}

use Devel::Size qw(total_size);
printf ("Total size of stats: %.1f KB\n", total_size($s)/1024);
printf ("Total size of cache: %.1f KB\n", total_size($obj->{'cache'})/1024);
