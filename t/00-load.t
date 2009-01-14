#!perl -T

use Test::More tests => 1;

BEGIN {
	use_ok( 'MooseX::Contract' );
}

diag( "Testing MooseX::Contract $MooseX::Contract::VERSION, Perl $], $^X" );
