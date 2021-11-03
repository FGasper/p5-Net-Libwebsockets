configure_requires 'ExtUtils::MakeMaker', '6.84';
configure_requires 'ExtUtils::MakeMaker::CPANfile', 0;
configure_requires 'ExtUtils::CChecker', 0;
configure_requires 'ExtUtils::PkgConfig', 0;

requires 'Promise::XS', 0;
requires 'URI::Split', 0;
requires 'X::Tiny', 0;

test_requires 'Test::More', 0;
test_requires 'Test::Deep', 0;
test_requires 'Test::FailWarnings', 0;
