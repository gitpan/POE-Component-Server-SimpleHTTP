# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl 1.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test::More tests => 3;
BEGIN {
	use_ok( 'POE::Component::Server::SimpleHTTP::Connection' );
	use_ok( 'POE::Component::Server::SimpleHTTP::Response' );
	use_ok( 'POE::Component::Server::SimpleHTTP' );
};

#########################