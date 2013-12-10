package NAP::Messaging::Exception::BadConfig;
use NAP::policy 'exception','tt';
use Data::Dump 'pp';

# ABSTRACT: exception for bad Producer configuration

=attr C<config_snippet>

the piece of the configuration that created problems

=cut

has config_snippet => ( is => 'ro', required => 1 );

=attr C<transformer>

the class of the producer / transformer involved

=cut

has transformer => ( is => 'ro', required => 1 );

=attr C<detail>

string explaining the problem

=cut

has detail => ( is => 'ro', isa => 'Str', required => 1 );

has '+message' => ( default => 'the configuration for transformer %{transformer}s is not usable: %{detail}s; relevant snippet: %{config_snippet_string}s' );

=method C<config_snippet_string>

Returns L</config_snippet> serialised via L<Data::Dump>.

=cut

sub config_snippet_string { pp $_[0]->config_snippet }
