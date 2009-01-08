name:      perl-Gearman-Client-Async
summary:   perl-Gearman-Client-Async - Gearman client libraries, for use inside a Danga::Socket event loop.
version:   0.94
release:   1
vendor:    Brad Fitzpatrick <brad@danga.com>
packager:  Jonathan Steinert <hachi@cpan.org>
license:   Artistic
group:     Applications/CPAN
buildroot: %{_tmppath}/%{name}-%{version}-%(id -u -n)
buildarch: noarch
source:    Gearman-Client-Async-%{version}.tar.gz
buildrequires: perl-Danga-Socket >= 1.52, perl-Gearman-Client
requires:  perl-Gearman-Client, perl-Danga-Socket >= 1.52
autoreq: no

%description
Gearman job distribution system

%prep
rm -rf "%{buildroot}"
%setup -n Gearman-Client-Async-%{version}

%build
%{__perl} Makefile.PL PREFIX=%{buildroot}%{_prefix}
make all
make test

%install
make pure_install

[ -x /usr/lib/rpm/brp-compress ] && /usr/lib/rpm/brp-compress


# remove special files
find %{buildroot} \(                    \
       -name "perllocal.pod"            \
    -o -name ".packlist"                \
    -o -name "*.bs"                     \
    \) -exec rm -f {} \;

# no empty directories
find %{buildroot}%{_prefix}             \
    -type d -depth -empty               \
    -exec rmdir {} \;

%clean
[ "%{buildroot}" != "/" ] && rm -rf %{buildroot}

%files
%defattr(-,root,root)
%{_prefix}/lib/*
%{_prefix}/share/man/man3
