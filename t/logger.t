#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use Test::FailWarnings;

use Net::Libwebsockets::Logger;

{
    my $logger = Net::Libwebsockets::Logger->new();
}

ok 'dummy';

done_testing;
