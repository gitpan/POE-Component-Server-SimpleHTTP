# Declare our package
package POE::Component::Server::SimpleHTTP::Connection;

# Standard stuff to catch errors
use strict qw(subs vars refs);				# Make sure we can't mess up
use warnings FATAL => 'all';				# Enable warnings to catch errors

# Initialize our version
our $VERSION = '1.01';

# Creates a new instance!
sub new {
	# Create the hash
	my $self = {};

	# Set stuff
	$self->{'Remote_IP'} = undef;
	$self->{'Remote_Port'} = undef;
	$self->{'Remote_Addr'} = undef;
	$self->{'Local_Addr'} = undef;

	# Bless ourself!
	bless( $self, 'POE::Component::Server::SimpleHTTP::Connection' );

	# All done!
	return $self;
}

# Gets the Remote_IP
sub Remote_IP {
	# Get ourself!
	my $self = shift;

	# Return the data
	return $self->{'Remote_IP'};
}

# Gets the Remote_Port
sub Remote_Port {
	# Get ourself!
	my $self = shift;

	# Return the data
	return $self->{'Remote_Port'};
}

# Gets the Remote_Addr
sub Remote_Addr {
	# Get ourself!
	my $self = shift;

	# Return the data
	return $self->{'Remote_Addr'};
}

# Gets the Local_Addr
sub Local_Addr {
	# Get ourself!
	my $self = shift;

	# Return the data
	return $self->{'Local_Addr'};
}

# End of module
1;

__END__
=head1 NAME

POE::Component::Server::SimpleHTTP::Connection - Stores connection information for SimpleHTTP

=head1 SYNOPSIS

	use POE::Component::Server::SimpleHTTP::Connection;
	my $connection = POE::Component::Server::SimpleHTTP::Connection->new();

	# Set data manually
	$connection->{'Remote_Port'} = 1024;

	# Get data automatically
	print $connection->Remote_Port;

=head1 CHANGES

=head2 1.01

	Initial Revision

=head1 DESCRIPTION

	This module simply holds some information from a SimpleHTTP connection.

=head2 METHODS

	my $connection = POE::Component::Server::SimpleHTTP::Connection->new();

	$connection->Remote_IP();	# Returns remote ip in dotted quad format ( 1.1.1.1 )
	$connection->Remote_Port();	# Returns remote port
	$connection->Remote_Addr();	# Returns true remote address, consult the L<Socket> POD
	$connection->Local_Addr();	# Returns true local address, same as above

=head2 EXPORT

Nothing.

=head1 SEE ALSO

	L<POE::Component::Server::SimpleHTTP>

=head1 AUTHOR

Apocalypse E<lt>apocal@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2003 by Apocalypse

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut