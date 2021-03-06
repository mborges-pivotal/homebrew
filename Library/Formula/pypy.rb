class Pypy < Formula
  homepage "http://pypy.org/"
  url "https://bitbucket.org/pypy/pypy/downloads/pypy-2.5.0-src.tar.bz2"
  sha1 "1d215a22ea16581de338700d556b21a8c02b4eff"

  bottle do
    cellar :any
    sha1 "54b80dd6f11ba20f01223473ec195d8a8b6afc6c" => :yosemite
    sha1 "9db7e2918b8bbcef2e83b2f86a6574e50bf34d33" => :mavericks
    sha1 "eee3b924556b45ca3128608b8ae02d367172fb53" => :mountain_lion
  end

  depends_on :arch => :x86_64
  depends_on "pkg-config" => :build
  depends_on "openssl"

  option "without-bootstrap", "Translate Pypy with system Python instead of " \
                              "downloading a Pypy binary distribution to " \
                              "perform the translation (adds 30-60 minutes " \
                              "to build)"

  resource "bootstrap" do
    url "https://bitbucket.org/pypy/pypy/downloads/pypy-2.5.0-osx64.tar.bz2"
    sha1 "ad47285526b1b3c14f4eecc874bb82a133a8e551"
  end

  resource "setuptools" do
    url "https://pypi.python.org/packages/source/s/setuptools/setuptools-12.0.5.tar.gz"
    sha1 "cd49661e090a397d77c690f7f2d06852b7086be9"
  end

  resource "pip" do
    url "https://pypi.python.org/packages/source/p/pip/pip-6.0.8.tar.gz"
    sha1 "bd59a468f21b3882a6c9d3e189d40c7ba1e1b9bd"
  end

  # https://bugs.launchpad.net/ubuntu/+source/gcc-4.2/+bug/187391
  fails_with :gcc

  def install
    # Having PYTHONPATH set can cause the build to fail if another
    # Python is present, e.g. a Homebrew-provided Python 2.x
    # See https://github.com/Homebrew/homebrew/issues/24364
    ENV["PYTHONPATH"] = ""
    ENV["PYPY_USESSION_DIR"] = buildpath

    python = "python"
    if build.with?("bootstrap") && OS.mac? && MacOS.preferred_arch == :x86_64
      resource("bootstrap").stage buildpath/"bootstrap"
      python = buildpath/"bootstrap/bin/pypy"
    end

    Dir.chdir "pypy/goal" do
      system python, buildpath/"rpython/bin/rpython",
             "-Ojit", "--shared", "--cc", ENV.cc, "--verbose",
             "--make-jobs", ENV.make_jobs, "targetpypystandalone.py"
      system "install_name_tool", "-change", "@rpath/libpypy-c.dylib", libexec/"lib/libpypy-c.dylib", "pypy-c"
      system "install_name_tool", "-id", opt_libexec/"lib/libpypy-c.dylib", "libpypy-c.dylib"
      (libexec/"bin").install "pypy-c" => "pypy"
      (libexec/"lib").install "libpypy-c.dylib"
    end

    (libexec/"lib-python").install "lib-python/2.7"
    libexec.install %w[include lib_pypy]

    # The PyPy binary install instructions suggest installing somewhere
    # (like /opt) and symlinking in binaries as needed. Specifically,
    # we want to avoid putting PyPy's Python.h somewhere that configure
    # scripts will find it.
    bin.install_symlink libexec/"bin/pypy"
    lib.install_symlink libexec/"lib/libpypy-c.dylib"

    %w[setuptools pip].each do |r|
      (libexec/r).install resource(r)
    end
  end

  def post_install
    # Precompile cffi extensions in lib_pypy
    # list from create_cffi_import_libraries in pypy/tool/release/package.py
    %w[_sqlite3 _curses syslog gdbm _tkinter].each do |module_name|
      quiet_system bin/"pypy", "-c", "import #{module_name}"
    end

    # Post-install, fix up the site-packages and install-scripts folders
    # so that user-installed Python software survives minor updates, such
    # as going from 1.7.0 to 1.7.1.

    # Create a site-packages in the prefix.
    prefix_site_packages.mkpath

    # Symlink the prefix site-packages into the cellar.
    libexec.install_symlink prefix_site_packages

    # Tell distutils-based installers where to put scripts
    scripts_folder.mkpath
    (distutils+"distutils.cfg").atomic_write <<-EOF.undent
      [install]
      install-scripts=#{scripts_folder}
    EOF

    %w[setuptools pip].each do |pkg|
      (libexec/pkg).cd do
        system bin/"pypy", "-s", "setup.py", "--no-user-cfg", "install",
               "--force", "--verbose"
      end
    end

    # Symlinks to easy_install_pypy and pip_pypy
    bin.install_symlink scripts_folder/"easy_install" => "easy_install_pypy"
    bin.install_symlink scripts_folder/"pip" => "pip_pypy"

    # post_install happens after linking
    %w[easy_install_pypy pip_pypy].each { |e| (HOMEBREW_PREFIX/"bin").install_symlink bin/e }
  end

  def caveats; <<-EOS.undent
    A "distutils.cfg" has been written to:
      #{distutils}
    specifying the install-scripts folder as:
      #{scripts_folder}

    If you install Python packages via "pypy setup.py install", easy_install_pypy,
    or pip_pypy, any provided scripts will go into the install-scripts folder
    above, so you may want to add it to your PATH *after* #{HOMEBREW_PREFIX}/bin
    so you don't overwrite tools from CPython.

    Setuptools and pip have been installed, so you can use easy_install_pypy and
    pip_pypy.
    To update setuptools and pip between pypy releases, run:
        pip_pypy install --upgrade pip setuptools

    See: https://github.com/Homebrew/homebrew/blob/master/share/doc/homebrew/Homebrew-and-Python.md
    EOS
  end

  # The HOMEBREW_PREFIX location of site-packages
  def prefix_site_packages
    HOMEBREW_PREFIX+"lib/pypy/site-packages"
  end

  # Where setuptools will install executable scripts
  def scripts_folder
    HOMEBREW_PREFIX+"share/pypy"
  end

  # The Cellar location of distutils
  def distutils
    libexec+"lib-python/2.7/distutils"
  end

  test do
    system bin/"pypy", "-c", "print('Hello, world!')"
    system scripts_folder/"pip", "list"
  end
end
