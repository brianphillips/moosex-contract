package MooseX::Contract;

use warnings;
use strict;

use Moose ();
use Carp qw(croak);
use Moose::Exporter;
use Moose::Util::TypeConstraints;
use Moose::Util qw(add_method_modifier find_meta);

Moose::Exporter->setup_import_methods(
	with_caller => [ qw(invariant contract) ],
	as_is => [qw(check assert accepts returns void)],
	also        => 'Moose',
);

=head1 NAME

MooseX::Contract - Helps you avoid Moose-stakes!

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';

=head1 WARNING

This module should be considered EXPERIMENTAL and should not be used in
critical applications unless you're willing to deal with all the typical
bugs that young, under-tested software has to offer!

=head1 SYNOPSIS

This module provides "Design by Contract" functionality using Moose
method hooks.

For example, in your Moose-built class:

	package MyEvenInt;

    use MooseX::Contract; # imports Moose for you!
	use Moose::Util::TypeConstraints;

	my $even_int = subtype 'Int', where { $_ % 2 == 0 };

	invariant assert { shift->{value} % 2 == 0 } '$self->{value} must be an even integer';

	has value => (
		is       => 'rw',
		isa      => $even_int,
		required => 1,
		default  => 0
	);

	contract 'add'
		=> accepts [ $even_int ]
		=> returns void;
	sub add {
		my $self = shift;
		my $incr = shift;
		$self->{value} += $incr;
		return;
	}

	contract 'get_multiple'
		=> accepts ['Int'],
		=> returns [$even_int];
	sub get_multiple {
		return shift->{value} * shift;
	}

	no MooseX::Contract;

=head1 EXPORT

=head2 invariant

This is a special kind of contract that adds a C<post> contract to all
public method calls.  Typically you would use this to assert a specific
characteristic about the object itself.

=head2 contract

This is the core method of the module.  It sets up a contract for a
specific method (or methods) and uses Moose's C<around> hook to execute
the C<pre> and C<post> contracts that are specified.

=head2 check

This is pure sugar and simply returns the CodeRef that is passed in.

=head2 assert

This helper method creates a wrapper contract that will C<croak> if the
underlying contract does not return a true value.

=head2 accepts

This helper method creates a C<pre> contract that looks at the value
or values passed in to the method by the caller.

=head2 returns

This helper method creates a C<post> contract that looks at the value
or values returned by the method it's affecting.

=head2 void

A simple helper method that asserts zero items were passed (useful in
specifying C<accepts> and C<returns> contracts).

=cut

our @CARP_NOT = qw(Class::MOP::Method::Wrapped);

sub assert(&;$);
sub void() { return assert { shift; @_ == 0 } "too many values (expected 0)" }

sub invariant {
	my $caller = shift;
	my %packages = map { $_ => 1 } ($caller, grep { ! ref($_) } @_);
	my @checks = map { (invar => $_) } grep { ref($_) eq 'CODE' } @_;
	contract(
		$caller,
		[
			map { $_->name }
			grep { exists( $packages{ $_->original_package_name } ) && $_->name ne 'meta' }
					find_meta($caller)->get_all_methods
		],
		@checks
	);
}

sub contract {
	return if($ENV{NO_MOOSEX_CONTRACT}); # bail if contracts are turned off
	my $caller = shift;
	my $method = shift; # could be a regex or ARRAY or scalar
	my %args = (pre => [], post => [], invar => []);
	if(@_ % 2){
		croak "contract must have even pairs of arguments: @_";
	}
	while(@_){
		my($type, $code) = splice(@_,0,2);
		if(!exists($args{$type})){
			croak "unknown contract type $type";
		}
		if(ref($code) ne 'CODE'){
			croak "invalid argument $code (should be a CodeRef";
		}
		push(@{ $args{ $type } }, $code);
	}
	add_method_modifier(
		$caller, 'around',
		[
			ref($method) eq 'ARRAY' ? @$method : $method,
			sub {
				my $next = shift;
				my ($self, @params) = @_;
				foreach my $m ( @{ $args{pre} } ) {
					eval { $m->($self, @params) };
						croak "pre contract error for $method: $@" if $@;
				}
				my @retval;
				# contortions to maintain calling context
				if(defined wantarray){
					if(wantarray){
						@retval = $next->(@_);
					} else {
						$retval[0] = $next->(@_);
					}
					foreach my $m ( @{ $args{post} } ) {
						eval { $m->($self, @retval) };
						croak "post contract error for $method: $@" if $@;
					}
				} else {
					# Hm... we don't evaluate the return value when we're in void context
					$next->(@_);
				}
				foreach my $m( @{ $args{invar} } ){
						eval { $m->($self) };
						croak "invariant contract error for $method: $@" if $@;
				}
				return defined(wantarray) ? wantarray ? @retval : $retval[0] : ();
			},
		]
	);
}

sub accepts($) {
	return if(!@_);
	my $accepts = shift;
	if(ref($accepts) eq 'ARRAY'){
		return pre => _make_type_validator( "accepts", $accepts);
	} elsif(ref($accepts) eq 'CODE'){
		return pre => $accepts;
	} else {
		croak "invalid parameter to accepts: $accepts";
	}
}

sub _make_type_validator {
	my $contract_name = shift;
	my @expected = map { Moose::Util::TypeConstraints::find_or_parse_type_constraint($_) } @{ $_[0] };
	return sub {
		my $self = shift;
		if ( @_ < @expected ) {
			croak "$contract_name contract expects at least " . @expected . " values, only " . @_ . " parameters passed";
		}
		for ( my $i = 0 ; $i < @_ ; $i++ ) {
			my $error = $expected[$i]->validate( $_[$i] );
			croak $error if $error;
		}
		return 1;
	};
}

sub returns($) {
	return if(!@_);
	my $returns = shift;
	if(ref($returns) eq 'ARRAY'){
		return post => _make_type_validator( "returns", $returns);
	} elsif(ref($returns) eq 'CODE') {
		return post => $returns;
	} else {
		croak "invalid parameter to accepts: $returns";
	}
}

sub check(&) { return @_ };

sub assert(&;$) {
	my($code, $message) = @_;
	$message ||= "assertion failed";
	return sub {
		$code->(@_) or croak $message;
	}
}

=head1 AUTHOR

Brian Phillips, C<< <bphillips at cpan.org> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-moosex-contract at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=MooseX-Contract>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc MooseX::Contract


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=MooseX-Contract>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/MooseX-Contract>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/MooseX-Contract>

=item * Search CPAN

L<http://search.cpan.org/dist/MooseX-Contract/>

=back


=head1 ACKNOWLEDGEMENTS


=head1 COPYRIGHT & LICENSE

Copyright 2009 Brian Phillips

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.


=cut

1; # End of MooseX::Contract
