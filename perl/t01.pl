#!/usr/bin/perl
BEGIN {
  push (@INC, ".");
}
use CacheSmart;
use Time::HiRes qw (sleep time);

my $MAX_KEYS = 100000;

my $obj = CacheSmart->new (
			   'name' => "My Test Cache"
			  );

my $result;
srand (143);
my $i = 0;
my $c_i = 1;
while ($i++ <= $MAX_KEYS) {
  my $k = "key" . int(rand($i*50000));
  my $v = "value: " . (rand($i). " ") x 12;
  my $r = rand(1);
  #print "about to set $k=$v\n";
  $obj->set ('key'      => $k,
	     'value'    => $v,
	     'context'  => "initialization$c_i" ,
	     # resource costs
	     'size'     => length($v),
	     'timecost' => $r
	    );
  if ($i % 23000 == 0) {
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

use Devel::Size qw(total_size);
print "Total size of stats: " . total_size($s)/1024 . " KBytes\n";
print "Total size of cache: " . total_size($obj->{'cache'})/1024 . " Kbytes\n";
