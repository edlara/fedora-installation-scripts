Name:      libdnf5-plugin-actions-timeshift
Version:   1.0.0
Release:   1.ell
Summary:   Timeshift plugin for DNF5
License:   LGPL-2.1-or-later

Source0:   timeshift.actions
Source1:   dnf-timeshift.logrotate

BuildArch: noarch

Provides:  %{name} = %{version}-%{release}

Requires:  timeshift >= 22.11.2-4%{?dist}
Requires:  libdnf5-plugin-actions >= 5.2.6.2-1%{?dist}
Requires:  bash >= 5.2.32-1%{?dist}
Requires:  logrotate >= 3.22.0-2%{?dist}
Requires:  util-linux-core >= 2.40.2-4%{?dist}

%description
Timeshift Action using libdnf5-plugin-actions for DNF5. Creates snapshot before and after every dnf transaction.

%install
  
  mkdir -p %{buildroot}%{_sysconfdir}/dnf/libdnf5-plugins/actions.d
  install -p -m 644 %{SOURCE0} %{buildroot}%{_sysconfdir}/dnf/libdnf5-plugins/actions.d/

  mkdir -p %{buildroot}%{_sysconfdir}/logrotate.d
  install -p -m 644 %{SOURCE1} %{buildroot}%{_sysconfdir}/logrotate.d/dnf-timeshift

%files
%{_sysconfdir}/dnf/libdnf5-plugins/actions.d/timeshift.actions
%{_sysconfdir}/logrotate.d/dnf-timeshift

%changelog
* Wed Oct  2 2024 Eduardo Lara <edward.lara.lara@gmail.com> - 1.0.0-1.ell
- Initial release of libdnf5 plugin action for timeshift
