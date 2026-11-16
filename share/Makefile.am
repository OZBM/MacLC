CLEANFILES =
MOSTLYCLEANFILES =
EXTRA_DIST =

LUA_MODULES = \
	lua/extensions/VLSub.lua \
	lua/intf/cli.lua \
	lua/intf/dummy.lua \
	lua/intf/dumpmeta.lua \
	lua/intf/http.lua \
	lua/intf/luac.lua \
	lua/intf/modules/host.lua \
	lua/intf/modules/httprequests.lua \
	lua/intf/telnet.lua \
	lua/meta/art/02_frenchtv.lua \
	lua/meta/art/03_lastfm.lua \
	lua/meta/art/01_googleimage.lua \
	lua/meta/art/00_musicbrainz.lua \
	lua/meta/reader/filename.lua \
	lua/modules/common.lua \
	lua/modules/dkjson.lua \
	lua/modules/sandbox.lua \
	lua/modules/simplexml.lua \
	lua/playlist/anevia_streams.lua \
	lua/playlist/anevia_xml.lua \
	lua/playlist/bbc_co_uk.lua \
	lua/playlist/cue.lua \
	lua/playlist/dailymotion.lua \
	lua/playlist/extreme.lua \
	lua/playlist/france2.lua \
	lua/playlist/jamendo.lua \
	lua/playlist/katsomo.lua \
	lua/playlist/koreus.lua \
	lua/playlist/lelombrik.lua \
	lua/playlist/mpora.lua \
	lua/playlist/newgrounds.lua \
	lua/playlist/pinkbike.lua \
	lua/playlist/rockbox_fm_presets.lua \
	lua/playlist/soundcloud.lua \
	lua/playlist/vimeo.lua \
	lua/playlist/vocaroo.lua \
	lua/playlist/twitch.lua \
	lua/playlist/zapiks.lua \
	lua/sd/fmc.lua \
	lua/sd/jamendo.lua \
	$(NULL)

LUA_MODULES_DOC = \
	$(NULL)

LUA_MODULES_PKGDATA = \
	lua/http/custom.lua \
	$(NULL)

EXTRA_DIST += \
	$(DIST_http_lua)

nobase_pkgdata_DATA =
nobase_pkglibexec_SCRIPTS =
nobase_dist_pkgdata_DATA =

#
# LUA
#
luac_verbose = $(luac_verbose_$(V))
luac_verbose_ = $(luac_verbose_$(AM_DEFAULT_VERBOSITY))
luac_verbose_0 = @echo "  LUAC     $@";

.lua.luac:
	$(AM_V_at)for f in $(EXTRA_DIST); do \
		test "$(srcdir)" = . || f="$(srcdir)/$$f"; \
		if test $$f = $<; then \
			exit 0; \
		fi; \
	done; \
	echo "Attempt to byte-compile unknown file: $(<)!"; \
	exit 1
	$(AM_V_at)$(MKDIR_P) "$$(dirname '$@')"
	$(luac_verbose)$(LUAC) -o $@ $<

if BUILD_LUA
nobase_pkglibexec_SCRIPTS += $(LUA_MODULES:%.lua=%.luac)
MOSTLYCLEANFILES += $(LUA_MODULES:%.lua=%.luac)
nobase_doc_DATA = \
	lua/README.txt \
	lua/extensions/README.txt \
	lua/http/requests/README.txt \
	lua/intf/README.txt \
	lua/intf/dumpmeta.lua \
	lua/meta/README.txt \
	lua/meta/art/README.txt \
	lua/meta/art/01_googleimage.lua \
	lua/meta/fetcher/README.txt \
	lua/meta/reader/README.txt \
	lua/meta/reader/filename.lua \
	lua/playlist/README.txt \
	lua/sd/README.txt \
	$(LUA_MODULES_DOC) \
	$(NULL)

nobase_dist_pkgdata_DATA += \
	lua/http/view.html \
	lua/http/mobile.html \
	lua/http/dialogs/create_stream.html \
	lua/http/dialogs/equalizer_window.html \
	lua/http/dialogs/mosaic_window.html \
	lua/http/dialogs/batch_window.html \
	lua/http/dialogs/error_window.html \
	lua/http/dialogs/browse_window.html \
	lua/http/dialogs/stream_window.html \
	lua/http/dialogs/offset_window.html \
	lua/http/dialogs/stream_config_window.html \
	lua/http/vlm.html \
	lua/http/images/buttons.png \
	lua/http/images/speaker-32.png \
	lua/http/images/vlc-48.png \
	lua/http/images/Audio-48.png \
	lua/http/images/Folder-48.png \
	lua/http/images/Other-48.png \
	lua/http/images/Back-48.png \
	lua/http/images/Video-48.png \
	lua/http/images/vlc16x16.png \
	lua/http/mobile_equalizer.html \
	lua/http/vlm_export.html \
	lua/http/mobile_browse.html \
	lua/http/favicon.ico \
	lua/http/mobile_view.html \
	lua/http/requests/playlist.xml \
	lua/http/requests/playlist.json \
	lua/http/requests/README.txt \
	lua/http/requests/playlist_jstree.xml \
	lua/http/requests/browse.xml \
	lua/http/requests/browse.json \
	lua/http/requests/vlm_cmd.xml \
	lua/http/requests/status.xml \
	lua/http/requests/status.json \
	lua/http/requests/rd.json \
	lua/http/requests/rd.xml \
	lua/http/requests/vlm.xml \
	lua/http/index.html \
	lua/http/css/ui-lightness/jquery-ui-1.8.13.custom.css \
	lua/http/css/ui-lightness/images/ui-bg_diagonals-thick_20_666666_40x40.png \
	lua/http/css/ui-lightness/images/ui-bg_flat_10_000000_40x100.png \
	lua/http/css/ui-lightness/images/ui-icons_ffffff_256x240.png \
	lua/http/css/ui-lightness/images/ui-bg_gloss-wave_35_f6a828_500x100.png \
	lua/http/css/ui-lightness/images/ui-bg_glass_65_ffffff_1x400.png \
	lua/http/css/ui-lightness/images/ui-icons_222222_256x240.png \
	lua/http/css/ui-lightness/images/ui-bg_glass_100_f6f6f6_1x400.png \
	lua/http/css/ui-lightness/images/ui-bg_highlight-soft_100_eeeeee_1x100.png \
	lua/http/css/ui-lightness/images/ui-bg_highlight-soft_75_ffe45c_1x100.png \
	lua/http/css/ui-lightness/images/ui-bg_diagonals-thick_18_b81900_40x40.png \
	lua/http/css/ui-lightness/images/ui-icons_ffd27a_256x240.png \
	lua/http/css/ui-lightness/images/ui-icons_228ef1_256x240.png \
	lua/http/css/ui-lightness/images/ui-icons_ef8c08_256x240.png \
	lua/http/css/ui-lightness/images/ui-bg_glass_100_fdf5ce_1x400.png \
	lua/http/css/main.css \
	lua/http/css/mobile.css \
	lua/http/js/ui.js \
	lua/http/js/common.js \
	lua/http/js/jquery.jstree.js \
	lua/http/js/controllers.js \
	$(LUA_MODULES_PKGDATA) \
	$(NULL)

endif
MOSTLYCLEANFILES += $(nobase_pkgdata_DATA)

EXTRA_DIST += \
	lua/README.txt \
	lua/extensions/README.txt \
	lua/intf/README.txt \
	lua/meta/README.txt \
	lua/meta/art/README.txt \
	lua/meta/fetcher/README.txt \
	lua/meta/reader/README.txt \
	lua/playlist/README.txt \
	lua/sd/README.txt \
	$(LUA_MODULES) \
	$(LUA_MODULES_DOC) \
	$(LUA_MODULES_PKGDATA) \
	$(NULL)


EXTRA_DIST += \
        hrtfs/dodeca_and_7channel_3DSL_HRTF.sofa
