%{!?dnf_lowest_compatible: %global dnf_lowest_compatible 4.4.3}

Name: python3-dnf-plugin-timeshift
Version: 1
Release: 1.ell
Summary: Timshift plugin for DNF
License: GPLv2+
Source0: timeshift.py

BuildArch:      noarch
BuildRequires:  python3-devel
BuildRequires:  python3-dnf >= %{dnf_lowest_compatible}

Requires:       python3-dnf-plugins-extras-common >= 4.0.15-1%{?dist}
%{?python_provide:%python_provide python3-dnf-plugins-extras-timeshift}
Requires:       timeshift
Provides:       %{name}-timeshift = %{version}-%{release}
Provides:       dnf-plugin-timeshift = %{version}-%{release}
Provides:       python3-%{name}-timeshift = %{version}-%{release}

%description
Timeshift Plugin for DNF, Python 3 version. Creates snapshot every transaction.

%install
  mkdir -p %{buildroot}%{python3_sitelib}/dnf-plugins/
  install -p -m 655 %{SOURCE0} %{buildroot}%{python3_sitelib}/dnf-plugins/

%files
%{python3_sitelib}/dnf-plugins/timeshift.*
%{python3_sitelib}/dnf-plugins/__pycache__/timeshift.*

%changelog
* Fri Dec 17 2021 Eduardo Lara <edward.lara.lara@gmail.com> - 1-1
- Initial release of Timeshift Plugin for DNF
