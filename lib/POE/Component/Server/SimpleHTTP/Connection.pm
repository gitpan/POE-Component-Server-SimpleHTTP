# Declare our package
package POE::Component::Server::SimpleHTTP::Connection;

# Standard stuff to catch errors
use strict qw(subs vars refs);				# Make sure we can't mess up
use warnings FATAL => 'all';				# Enable warnings to catch errors

# Initialize our version
our $VERSION = '1.03';

# Creates a new instance!
sub new {
	# Create the hash
	my $self = {};

	# Set stuff
	$self->{'remote_ip'} = shift;
	$self->{'remote_port'} = shift;
	$self->{'remote_addr'} = shift;
	$self->{'local_addr'} = shift;

	# Bless ourself!
	bless( $self, 'POE::Component::Server::SimpleHTTP::Connection' );

	# All done!
	return $self;
}

# Gets the remote_ip
sub remote_ip {
	# Get ourself!
	my $self = shift;

	# Return the data
	return $self->{'remote_ip'};
}

# Gets the remote_port
sub remote_port {
	# Get ourself!
	my $self = shift;

	# Return the data
	return $self->{'remote_port'};
}

# Gets the remote_addr
sub remote_addr {
	# Get ourself!
	my $self = shift;

	# Return the data
	return $self->{'remote_addr'};
}

# Gets the local_addr
sub local_addr {
	# Get ourself!
	my $self = shift;

	# Return the data
	return $self->{'local_addr'};
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
	$connection->{'remote_port'} = 1024;

	# Get data automatically
	print $connection->remote_port;

=head1 CHANGES

=head2 1.02

	Got rid of funky CaPs in methods

=head2 1.01

	Initial Revision

=head1 DESCRIPTION

	This module simply holds some information from a SimpleHTTP connection.

=head2 METHODS

	my $connection = POE::Component::Server::SimpleHTTP::Connection->new();

	$connection->remote_ip();	# Returns remote ip in dotted quad format ( 1.1.1.1 )
	$connection->remote_port();	# Returns remote port
	$connection->remote_addr();	# Returns true remote address, consult the L<Socket> POD
	$connection->local_addr();	# Returns true local address, same as above

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