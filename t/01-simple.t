#!/usr/bin/perl -w

use warnings;
use strict;

use HTTP::Request::Common;
use MongoDB;
use Plack::Middleware::PyeLogger;
use Plack::Test;
use Test::More tests => 3;

my $conn;
eval { $conn = MongoDB::MongoClient->new; };

SKIP: {
	if ($@) {
		diag("MongoDB needs to be running for this test.");
		skip("MongoDB needs to be running for this test.", 3);
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
		opts => {
			log_db => 'test',
			log_coll => 'pye_logs',
			session_coll => 'pye_sessions',
			be_safe => 1
		}
	);

	test_psgi $app, sub {
		my $cb = shift;

		my $db = $conn->get_database('test');
		my $lcoll = $db->get_collection('pye_logs');
		my $scoll = $db->get_collection('pye_sessions');

		my $res = $cb->(GET "/");

		my @logs = $lcoll->find->sort({ date => -1 })->all;

		is($logs[0]->{text}, 'Message #1', 'first message logged');
		is_deeply($logs[1]->{data}, { some => 'data' }, 'second message logged');

		my @sessions = $scoll->find->all;
		is($sessions[0]->{_id}, '1', 'only session exists');

		$lcoll->drop;
		$scoll->drop;
	};
}

done_testing;