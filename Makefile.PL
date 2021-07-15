
#$_ = q<> for my ($cflags, $lflags);

my @extra_cflags = qw<
    -I/Users/felipe/code/libwebsockets/build/include
>;

my @extra_lflags = qw(
    -Wl,-rpath,/Users/felipe/code/libwebsockets/build/lib
    -L/Users/felipe/code/libwebsockets/build/lib
    -lwebsockets
);

use Config;

use ExtUtils::CChecker;
use ExtUtils::PkgConfig;

my $PKG = 'libwebsockets';

#if (!ExtUtils::PkgConfig->exists($PKG)) {
#    die "Your pkg-config can’t find $PKG; aborting …\n";
#}
#
#my $pc_cflags = ExtUtils::PkgConfig->cflags($PKG);
#my $pc_libs = ExtUtils::PkgConfig->libs($PKG);

my @cflags = (
#    split( m< >, $pc_cflags ),
    @extra_cflags,
);

my @lflags = (
#    split( m< >, $pc_libs ),
    @extra_lflags,
);

my $cc = ExtUtils::CChecker->new( quiet => 0 );
$cc->push_extra_compiler_flags(@cflags);
$cc->push_extra_linker_flags(@lflags);

{
    print "Does your LWS support custom event loops?\n";

    my $has_event_c = <<END;
    #include <libwebsockets.h>

    int main() {
        int foo = LWS_EV_READ;
        return 0;
    }
END

    if ( $cc->try_compile_run($has_event_c) ) {
        print "... yes! (Whew ...)\n";
    }
    else {
        die "... apparently not. :(\n";
    }
}

my $lws_has_deflate = do {
    print "Does your LWS support permessage-deflate?\n";

    my $has_deflate_c = <<END;
    #include <libwebsockets.h>

    void * funcptr = lws_extension_callback_pm_deflate;

    int main() {
        return 0;
    }
END

    my $lws_has_deflate = $cc->try_compile_run($has_deflate_c);

    if ($lws_has_deflate) {
        print "... yes!\n";
    }
    else {
        print "... apparently not. :(\n";
    }

    $lws_has_deflate;
};

use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'Net::Libwebsockets',
    VERSION_FROM      => 'lib/Net/Libwebsockets.pm', # finds $VERSION
    ABSTRACT_FROM  => 'lib/Net/Libwebsockets.pm', # retrieve abstract from module
    AUTHOR         => [
        'Felipe Gasper (FELIPE)',
    ],
    LIBS              => ["@lflags"], # e.g., '-lm'
    DEFINE            => $lws_has_deflate ? '-DNLWS_LWS_HAS_PMD' : '',
    LICENSE           => "perl_5",

    INC => "-Wall -I. --std=c99 @cflags",

    # An awful hack to accommodate the fact that otherwise
    # the created Makefile expects xshelper.o to be in the base dir:
    CCFLAGS => "$Config{'ccflags'} -o \$@",

    OBJECT => [
        '$(BASEEXT)$(OBJ_EXT)',
        'nlws_courier.o',
        'nlws_frame.o',
        'nlws_perl_loop.o',
        'xshelper/xshelper.o',
    ],

    CONFIGURE_REQUIRES => {

        # In order to specify OBJECT as an array.
        'ExtUtils::MakeMaker' => 6.84,
        'ExtUtils::CChecker' => 0,
        'ExtUtils::PkgConfig' => 0,
    },

    META_MERGE => {
        'meta-spec' => { version => 2 },
        resources => {
            repository => {
                type => 'git',
                url => 'git://github.com/FGasper/p5-Net-Libwebsockets.git',
                web => 'https://github.com/FGasper/p5-Net-Libwebsockets',
            },
            bugtracker => {
                web => 'https://github.com/FGasper/p5-Net-Libwebsockets/issues',
            },
        },
    },

    PREREQ_PM => {
        'Promise::XS' => 0,
        'URI::Split' => 0,
        'IO::FDSaver' => 0,
    },

    TEST_REQUIRES => {
        'Test::More' => 0,
        'Test::Deep' => 0,
        'Test::FailWarnings' => 0,
        'File::Temp' => 0,
    },
);
