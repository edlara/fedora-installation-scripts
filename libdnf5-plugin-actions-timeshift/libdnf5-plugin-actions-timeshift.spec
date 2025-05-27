Name:      libdnf5-plugin-actions-timeshift
Version:   1.2
Release:   1.ell
Summary:   Timeshift plugin for DNF5
License:   LGPL-2.1-or-later

Source0:   timeshift.actions
Source1:   dnf5-timeshift.conf
Source2:   dnf5-timeshift-delete-old-snapshots
Source3:   dnf5-timeshift.logrotate

BuildArch: noarch

Provides:  %{name} = %{version}-%{release}

Requires:  timeshift >= 22.11.2-6%{?dist}
Requires:  libdnf5-plugin-actions >= 5.2.11.0-1%{?dist}
Requires:  bash >= 5.2.37-1%{?dist}
Requires:  logrotate >= 3.22.0-3%{?dist}
Requires:  util-linux-core >= 2.40.4-7%{?dist}

%description
Timeshift Action using libdnf5-plugin-actions for DNF5. Creates snapshot before and after every dnf transaction.

%install
  
  %__install -D -p -m0644 %{SOURCE0} %{buildroot}%{_sysconfdir}/dnf/libdnf5-plugins/actions.d/timeshift.actions
  %__install -D -p -m0644 %{SOURCE1} %{buildroot}%{_sysconfdir}/dnf5-timeshift.conf
  %__install -D -p -m0755 %{SOURCE2} %{buildroot}%{_bindir}/dnf5-timeshift-delete-old-snapshots
  %__install -D -p -m0644 %{SOURCE3} %{buildroot}%{_sysconfdir}/logrotate.d/dnf5-timeshift

%files
%{_sysconfdir}/dnf/libdnf5-plugins/actions.d/timeshift.actions
%{_sysconfdir}/dnf5-timeshift.conf
%{_bindir}/dnf5-timeshift-delete-old-snapshots
%{_sysconfdir}/logrotate.d/dnf5-timeshift

%changelog
* Tue May 27 2025 Eduardo Lara <edward.lara.lara@gmail.com> - 1.2-1.ell
- _sbindir deprectated, moving to _bindir

* Tue Mar 18 2025 Eduardo Lara <edward.lara.lara@gmail.com> - 1.1-2.ell
- Recompiling for Fedora 42

* Wed Dec 25 2024 Eduardo Lara <edward.lara.lara@gmail.com> - 1.1-1.ell
- Removing post_snapshot.

* Sat Oct  5 2024 Eduardo Lara <edward.lara.lara@gmail.com> - 1.0.1-1.ell
- Correcting logrotate file name to use dnf5

* Sat Oct  5 2024 Eduardo Lara <edward.lara.lara@gmail.com> - 1.0.1-1.ell
- Updating file names and log format
- Adding snapshot deletion

* Wed Oct  2 2024 Eduardo Lara <edward.lara.lara@gmail.com> - 1.0.0-1.ell
- Initial release of libdnf5 plugin action for timeshift
