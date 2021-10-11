package Net::Libwebsockets::Logger;

use strict;
use warnings;

use Carp;

sub new {
    my ($class, %opts) = @_;

    for my $key (keys %opts) {
        if ($key eq 'level') {
            # validate? XS will handle it anyway
        }
        elsif ($key eq 'callback') {
            if ($opts{$key} && !UNIVERSAL::isa($opts{$key}, 'CODE')) {
                Carp::confess("“callback” must be a coderef, not “$opts{$key}”");
            }
        }
        else {
            Carp::confess(__PACKAGE__ . ": unknown argument: $key");
        }
    }

    $opts{'level'} ||= 0;

    return $class->_new(@opts{'level', 'callback'});
}

1;
