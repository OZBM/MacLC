loggerdir = $(pluginsdir)/logger
logger_PLUGINS =
logger_LTLIBRARIES =
if HAVE_PARTIAL_LINKING
noinst_LTLIBRARIES += $(logger_PLUGINS)
else
logger_LTLIBRARIES += $(logger_PLUGINS)
endif

libconsole_logger_plugin_la_SOURCES = logger/console.c
libfile_logger_plugin_la_SOURCES = logger/file.c
logger_PLUGINS += libconsole_logger_plugin.la libfile_logger_plugin.la

libsyslog_plugin_la_SOURCES = logger/syslog.c
if HAVE_SYSLOG
logger_PLUGINS += libsyslog_plugin.la
endif

libjson_tracer_plugin_la_SOURCES = logger/json.c
logger_PLUGINS += libjson_tracer_plugin.la

AM_V_LTCARGO = $(AM_V_LTCARGO_$(V))
AM_V_LTCARGO_ = $(AM_V_LTCARGO_$(AM_DEFAULT_VERBOSITY))
AM_V_LTCARGO__0 = $(AM_V_LTCARGO_0)
AM_V_LTCARGO_0 = @echo "  CARGO  $(@)";

libtelegraf_rs.la: $(libtelegraf_rs_plugin_la_SOURCES)
	$(AM_V_LTCARGO)$(LIBTOOL_CARGO) $(abs_srcdir)/logger/telegraf-rs $@
CLEANFILES += libtelegraf_rs.la

libtelegraf_rs_plugin_la_SOURCES = \
	logger/telegraf-rs/Cargo.toml \
	logger/telegraf-rs/src/lib.rs
libtelegraf_rs_plugin_la_LIBADD = libtelegraf_rs.la

if HAVE_RUST
logger_PLUGINS += libtelegraf_rs_plugin.la
endif
