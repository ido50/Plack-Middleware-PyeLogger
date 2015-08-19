#!/usr/bin/perl -w

use warnings;
use strict;

use HTTP::Request::Common;
use MongoDB;
use Plack::Middleware::PyeLogger;
use Plack::Test;
use Test::More tests => 2;

my $conn;
eval { $conn = MongoDB::MongoClient->new; };

SKIP: {
	if ($@) {
		diag("MongoDB needs to be running for this test.");
		skip("MongoDB needs to be running for this test.", 2);
	}

	my @messages = (
		{ session_id => 1, message => 'Message #1' },
		{ session_id => 1, message => 'Message #2', data => { some => 'data' } }
	);

	my $app = sub {
		my $env = shift;

		map { $env->{'psgix.logger'}->($_) } @messages;

		return [200, [], []];
	};

	$app = Plack::Middleware::PyeLogger->wrap($app,
		backend => 'MongoDB',
		opts => {
			database => 'test',
			collection => 'pye_test_logs',
			be_safe => 1
		}
	);

	test_psgi $app, sub {
		my $cb = shift;

		my $db = $conn->get_database('test');
		my $coll = $db->get_collection('pye_test_logs');

		my $res = $cb->(GET "/");

		my @logs = $coll->find->sort({ date => 1 })->all;

		is($logs[0]->{text}, 'Message #1', 'first message logged');
		is_deeply($logs[1]->{data}, { some => 'data' }, 'second message logged');

		$coll->drop;
	};
}

done_testing;
