
#$_ = q<> for my ($cflags, $lflags);

my $cflags = q<-I/Users/felipe/code/libwebsockets/build/include>;
my $lflags = '-L/Users/felipe/code/libwebsockets/build/lib -lwebsockets';

use Devel::PPPort;

Devel::PPPort::WriteFile();

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
    LIBS              => [$lflags], # e.g., '-lm'
    DEFINE            => '', # e.g., '-DHAVE_SOMETHING'
    INC               => "-Wall -I. --std=c99 $cflags",
    LICENSE           => "perl_5",

    OBJECT => [
        '$(BASEEXT)$(OBJ_EXT)',
        'nlws_courier.o',
        'nlws_frame.o',
        'nlws_perl_loop.o',
        'xshelper/xshelper.o',
    ],

    LDFROM => join(
        q< >,
        '$(BASEEXT)$(OBJ_EXT)',
        'nlws_courier.o',
        'nlws_frame.o',
        'nlws_perl_loop.o',
        'xshelper.o',
    ),

    CONFIGURE_REQUIRES => {

        # In order to specify OBJECT as an array.
        'ExtUtils::MakeMaker' => 6.84,
        'Devel::PPPort' => 0,
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
