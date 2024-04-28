%{!?dnf_lowest_compatible: %global dnf_lowest_compatible 4.4.3}

Name: python3-dnf-plugin-timeshift
Version: 1.0.9
Release: 1.ell
Summary: Timeshift plugin for DNF
License: GPLv2+
Source0: timeshift.py

BuildArch:      noarch
BuildRequires:  python3-devel
BuildRequires:  python3-dnf >= %{dnf_lowest_compatible}

Requires:       python3-dnf-plugins-extras-common = 4.1.2-1%{?dist}
%{?python_provide:%python_provide python3-dnf-plugins-extras-timeshift}
Requires:       timeshift
Provides:       %{name}-timeshift = %{version}-%{release}
Provides:       dnf-plugin-timeshift = %{version}-%{release}
Provides:       python3-%{name}-timeshift = %{version}-%{release}

%description
Timeshift Plugin for DNF, Python 3 version. Creates snapshot every transaction.

%install
  mkdir -p %{buildroot}%{python3_sitelib}/dnf-plugins/
  install -p -m 644 %{SOURCE0} %{buildroot}%{python3_sitelib}/dnf-plugins/

%files
%{python3_sitelib}/dnf-plugins/timeshift.*
%{python3_sitelib}/dnf-plugins/__pycache__/timeshift.*

%changelog
* Sun Apr 28 2024 Eduardo Lara <edward.lara.lara@gmail.com> - 1.0.9-1.ell
- Recompiled for Fedora 40

* Sun Apr 28 2024 Eduardo Lara <edward.lara.lara@gmail.com> - 1.0.8-2.ell
- Recompiled for python3-dnf-plugins-extras-common 4.1.2-1

* Fri Nov 10 2023 Eduardo Lara <edward.lara.lara@gmail.com> - 1.0.8-1.ell
- Recompiled for Fedora 39

* Fri Nov 10 2023 Eduardo Lara <edward.lara.lara@gmail.com> - 1.0.7-1.ell
- Updating to python3-dnf-plugins-extras-common 4.1 on Fedpra 38

* Sun Sep 24 2023 Eduardo Lara <edward.lara.lara@gmail.com> - 1.0.6-1.ell
- Recompiled for Fedora 39

* Sat Apr 22 2023 Eduardo Lara <edward.lara.lara@gmail.com> - 1.0.5-1.ell
- Recompiled for Fedora 38

* Sat Apr 22 2023 Eduardo Lara <edward.lara.lara@gmail.com> - 1.0.4-1.ell
- Updating to python3-dnf-plugins-extras-common 4.1

* Tue Sep 13 2022 Eduardo Lara <edward.lara.lara@gmail.com> - 1.0.3-1.ell
- Recompiled for Fedora 37

* Mon Apr  4 2022 Eduardo Lara <edward.lara.lara@gmail.com> - 1.0.2-1.ell
- Recompiled for Fedora 36

* Sat Dec 18 2021 Eduardo Lara <edward.lara.lara@gmail.com> - 1.0.1-1.ell
- Requiring exact version of python3-dnf-plugins-extras-common
- Fixing plugin permissions
- Fixing typo

* Fri Dec 17 2021 Eduardo Lara <edward.lara.lara@gmail.com> - 1-1.ell
- Initial release of Timeshift Plugin for DNF
