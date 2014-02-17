#!perl
use NAP::policy 'tt';
use NAP::Messaging::MultiRunner;
NAP::Messaging::MultiRunner->new('MyApp')->run_multiple;
