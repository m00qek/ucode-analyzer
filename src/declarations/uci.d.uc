// Source: https://github.com/jow-/ucode
// Versions: 2025.07.18~3f64c808, 2026.01.16~85922056
/**
 * # OpenWrt UCI configuration
 *
 * The `uci` module provides access to the native OpenWrt
 * {@link https://github.com/openwrt/uci libuci} API for reading and
 * manipulating UCI configuration files.
 *
 * Functions can be individually imported and directly accessed using the
 * {@link https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Statements/import#named_import named import}
 * syntax:
 *
 *   ```
 *   import { cursor } from 'uci';
 *
 *   let ctx = cursor();
 *   let hostname = ctx.get_first('system', 'system', 'hostname');
 *   ```
 *
 * Alternatively, the module namespace can be imported
 * using a wildcard import statement:
 *
 *   ```
 *   import * as uci from 'uci';
 *
 *   let ctx = uci.cursor();
 *   let hostname = ctx.get_first('system', 'system', 'hostname');
 *   ```
 *
 * Additionally, the uci module namespace may also be imported by invoking
 * the `ucode` interpreter with the `-luci` switch.
 *
 * @module uci
 */

/**
 * UCI cursor returned by {@link module:uci#cursor|cursor()}.
 *
 * @typedef {{
 *   load: function(string): ?boolean,
 *   unload: function(string): ?boolean,
 *   get: function(string, ?string, ?string): ?(string|string[]),
 *   get_all: function(?string, ?string): ?*,
 *   get_first: function(string, string, ?string): ?(string|string[]),
 *   add: function(string, string): ?string,
 *   set: function(string, string, *, ?*): ?boolean,
 *   delete: function(string, string, ?string): ?boolean,
 *   list_append: function(string, string, string, *): ?boolean,
 *   list_remove: function(string, string, string, *): ?boolean,
 *   rename: function(string, string, string, string): ?boolean,
 *   reorder: function(string, string, int): ?boolean,
 *   save: function(?string): ?boolean,
 *   commit: function(?string): ?boolean,
 *   revert: function(?string): ?boolean,
 *   changes: function(?string): ?*,
 *   foreach: function(string, ?string, function): ?boolean,
 *   configs: function(): ?string[]
 * }} UciCursor
 */

/**
 * Query error information.
 *
 * Returns a string containing a description of the last occurred error or
 * `null` if there is no error information.
 *
 * @function module:uci#error
 *
 * @returns {?string}
 *
 * @example
 * // Trigger error
 * const ctx = cursor();
 * ctx.set("not_existing_config", "test", "1");
 *
 * // Print error (should yield "Entry not found")
 * print(ctx.error(), "\n");
 */
export function error() {};

/**
 * Instantiate uci cursor.
 *
 * A uci cursor is a context for interacting with uci configuration files. It's
 * purpose is to cache and hold changes made to loaded configuration states
 * until those changes are written out to disk or discarded.
 *
 * Unsaved and uncommitted changes in a cursor instance are private and not
 * visible to other cursor instances instantiated by the same program or other
 * processes on the system.
 *
 * Returns the instantiated cursor on success.
 *
 * Returns `null` on error, e.g. if an invalid path argument was provided.
 *
 * @function module:uci#cursor
 *
 * @param {string} [config_dir=/etc/config]
 * The directory to search for configuration files. It defaults to the well
 * known uci configuration directory `/etc/config` but may be set to a different
 * path for special purpose applications.
 *
 * @param {string} [delta_dir=/tmp/.uci]
 * The directory to save delta records in. It defaults to the well known
 * `/tmp/.uci` path which is used as default by the uci command line tool.
 *
 * By changing this path to a different location, it is possible to isolate
 * uncommitted application changes from the uci cli or other processes on the
 * system.
 *
 * @param {string} [config2_dir=/var/run/uci]
 * The directory to keep override config files in. Files are in the same format
 * as in config_dir, but can individually override ones from that directory.
 * It defaults to the uci configuration directory `/var/run/uci` but may be
 * set to a different path for special purpose applications, or even disabled
 * by setting this parameter to an empty string.
 *
 * @param {int} [flags]
 * Parser flags to change.
 *
 * @returns {?UciCursor}
 */
export function cursor(config_dir, delta_dir, config2_dir) {};

/**
 * Explicitly reload configuration file.
 *
 * Usually, any attempt to query or modify a value within a given configuration
 * will implicitly load the underlying file into memory. By invoking `load()`
 * explicitly, a potentially loaded stale configuration is discarded and
 * reloaded from the file system, ensuring that the latest state is reflected in
 * the cursor.
 *
 * Returns `true` if the configuration was successfully loaded.
 *
 * Returns `null` on error, e.g. if the requested configuration does not exist.
 *
 * @function module:uci.cursor#load
 *
 * @param {string} config
 * The name of the configuration file to load, e.g. `"system"` to load
 * `/etc/config/system` into the cursor.
 *
 * @returns {?boolean}
 */

/**
 * Explicitly unload configuration file.
 *
 * The `unload()` function forcibly discards a loaded configuration state from
 * the cursor so that the next attempt to read or modify that configuration
 * will load it anew from the file system.
 *
 * Returns `true` if the configuration was successfully unloaded.
 *
 * Returns `false` if the configuration was not loaded to begin with.
 *
 * Returns `null` on error, e.g. if the requested configuration does not exist.
 *
 * @function module:uci.cursor#unload
 *
 * @param {string} config
 * The name of the configuration file to unload.
 *
 * @returns {?boolean}
 */

/**
 * Query a single option value or section type.
 *
 * When invoked with three arguments, the function returns the value of the
 * given option, within the specified section of the given configuration.
 *
 * When invoked with just a config and section argument, the function returns
 * the type of the specified section.
 *
 * In either case, the given configuration is implicitly loaded into the cursor
 * if not already present.
 *
 * Returns the configuration value or section type on success.
 *
 * Returns `null` on error, e.g. if the requested configuration does not exist
 * or if an invalid argument was passed.
 *
 * @function module:uci.cursor#get
 *
 * @param {string} config
 * The name of the configuration file to query, e.g. `"system"` to query values
 * in `/etc/config/system`.
 *
 * @param {string} section
 * The name of the section to query within the configuration.
 *
 * @param {string} [option]
 * The name of the option to query within the section. If omitted, the type of
 * the section is returned instead.
 *
 * @returns {?(string|string[])}
 *
 * @example
 * const ctx = cursor(…);
 *
 * // Query an option, extended section notation is supported
 * ctx.get('system', '@system[0]', 'hostname');
 *
 * // Query a section type (should yield 'interface')
 * ctx.get('network', 'lan');
 */

/**
 * Query a complete section or configuration.
 *
 * When invoked with two arguments, the function returns all values of the
 * specified section within the given configuration as dictionary.
 *
 * When invoked with just a config argument, the function returns a nested
 * dictionary of all sections present within the given configuration.
 *
 * In either case, the given configuration is implicitly loaded into the cursor
 * if not already present.
 *
 * Returns the section or configuration dictionary on success.
 *
 * Returns `null` on error, e.g. if the requested configuration does not exist
 * or if an invalid argument was passed.
 *
 * @function module:uci.cursor#get_all
 *
 * @param {string} config
 * The name of the configuration file to query, e.g. `"system"` to query values
 * in `/etc/config/system`.
 *
 * @param {string} [section]
 * The name of the section to query within the configuration. If omitted a
 * nested dictionary containing all section values is returned.
 *
 * @returns {?*}
 *
 * @example
 * const ctx = cursor(…);
 *
 * // Query all lan interface details
 * ctx.get_all('network', 'lan');
 *
 * // Dump the entire dhcp configuration
 * ctx.get_all('dhcp');
 */

/**
 * Query option value or name of first section of given type.
 *
 * When invoked with three arguments, the function returns the value of the
 * given option within the first found section of the specified type in the
 * given configuration.
 *
 * When invoked with just a config and section type argument, the function
 * returns the name of the first found section of the given type.
 *
 * In either case, the given configuration is implicitly loaded into the cursor
 * if not already present.
 *
 * Returns the configuration value or section name on success.
 *
 * Returns `null` on error, e.g. if the requested configuration does not exist
 * or if an invalid argument was passed.
 *
 * @function module:uci.cursor#get_first
 *
 * @param {string} config
 * The name of the configuration file to query, e.g. `"system"` to query values
 * in `/etc/config/system`.
 *
 * @param {string} type
 * The section type to find the first section for within the configuration.
 *
 * @param {string} [option]
 * The name of the option to query within the section. If omitted, the name of
 * the section is returned instead.
 *
 * @returns {?(string|string[])}
 *
 * @example
 * const ctx = cursor(…);
 *
 * // Query hostname in first anonymous "system" section of /etc/config/system
 * ctx.get_first('system', 'system', 'hostname');
 *
 * // Figure out name of first network interface section (usually "loopback")
 * ctx.get_first('network', 'interface');
 */

/**
 * Add anonymous section to given configuration.
 *
 * Adds a new anonymous (unnamed) section of the specified type to the given
 * configuration. In order to add a named section, the three argument form of
 * `set()` should be used instead.
 *
 * In contrast to other query functions, `add()` will not implicitly load the
 * configuration into the cursor. The configuration either needs to be loaded
 * explicitly through `load()` beforehand, or implicitly by querying it through
 * one of the `get()`, `get_all()`, `get_first()` or `foreach()` functions.
 *
 * Returns the autogenerated, ephemeral name of the added unnamed section
 * on success.
 *
 * Returns `null` on error, e.g. if the targeted configuration was not loaded or
 * if an invalid section type value was passed.
 *
 * @function module:uci.cursor#add
 *
 * @param {string} config
 * The name of the configuration file to add the section to, e.g. `"system"` to
 * modify `/etc/config/system`.
 *
 * @param {string} type
 * The type value to use for the added section.
 *
 * @returns {?string}
 *
 * @example
 * const ctx = cursor(…);
 *
 * // Load firewall configuration
 * ctx.load('firewall');
 *
 * // Add unnamed `config rule` section
 * const sid = ctx.add('firewall', 'rule');
 *
 * // Set values on the newly added section
 * ctx.set('firewall', sid, 'name', 'A test');
 * ctx.set('firewall', sid, 'target', 'ACCEPT');
 * …
 */

/**
 * Set option value or add named section in given configuration.
 *
 * When invoked with four arguments, the function sets the value of the given
 * option within the specified section of the given configuration to the
 * provided value. A value of `""` (empty string) can be used to delete an
 * existing option.
 *
 * When invoked with three arguments, the function adds a new named section to
 * the given configuration, using the specified type.
 *
 * In either case, the given configuration is implicitly loaded into the cursor
 * if not already present.
 *
 * Returns `true` if the named section was added or the specified option was
 * set.
 *
 * Returns `null` on error, e.g. if the targeted configuration was not found or
 * if an invalid value was passed.
 *
 * @function module:uci.cursor#set
 *
 * @param {string} config
 * The name of the configuration file to set values in, e.g. `"system"` to
 * modify `/etc/config/system`.
 *
 * @param {string} section
 * The section name to create or set a value in.
 *
 * @param {string} option_or_type
 * The option name to set within the section or, when the subsequent value
 * argument is omitted, the type of the section to create within the
 * configuration.
 *
 * @param {(Array<string|boolean|int>|string|boolean|int)} [value]
 * The option value to set.
 *
 * @returns {?boolean}
 *
 * @example
 * const ctx = cursor(…);
 *
 * // Add named `config interface guest` section
 * ctx.set('network', 'guest', 'interface');
 *
 * // Set values on the newly added section
 * ctx.set('network', 'guest', 'proto', 'static');
 * ctx.set('network', 'guest', 'ipaddr', '10.0.0.1/24');
 * ctx.set('network', 'guest', 'dns', ['8.8.4.4', '8.8.8.8']);
 * …
 *
 * // Delete 'disabled' option in first wifi-iface section
 * ctx.set('wireless', '@wifi-iface[0]', 'disabled', '');
 */

/**
 * Delete an option or section from given configuration.
 *
 * When invoked with three arguments, the function deletes the given option
 * within the specified section of the given configuration.
 *
 * When invoked with two arguments, the function deletes the entire specified
 * section within the given configuration.
 *
 * In either case, the given configuration is implicitly loaded into the cursor
 * if not already present.
 *
 * Returns `true` if specified option or section has been deleted.
 *
 * Returns `null` on error, e.g. if the targeted configuration was not found or
 * if an invalid value was passed.
 *
 * @function module:uci.cursor#delete
 *
 * @param {string} config
 * The name of the configuration file to delete values in, e.g. `"system"` to
 * modify `/etc/config/system`.
 *
 * @param {string} section
 * The section name to remove the specified option in or, when the subsequent
 * argument is omitted, the section to remove entirely.
 *
 * @param {string} [option]
 * The option name to remove within the section.
 *
 * @returns {?boolean}
 *
 * @example
 * const ctx = cursor(…);
 *
 * // Delete 'disabled' option in first wifi-iface section
 * ctx.delete('wireless', '@wifi-iface[0]', 'disabled');
 *
 * // Delete 'wan' interface
 * ctx.delete('network', 'lan');
 *
 * // Delete last firewall rule
 * ctx.delete('firewall', '@rule[-1]');
 */

/**
 * Add an item to a list option in given configuration.
 *
 * Adds a single value to an existing list option within the specified section
 * of the given configuration. The configuration is implicitly loaded into the
 * cursor if not already present.
 *
 * The new value is appended to the end of the list, maintaining the existing order.
 * No attempt is made to check for or remove duplicate values.
 *
 * Returns `true` if the item was successfully added to the list.
 *
 * Returns `null` on error, e.g. if the targeted option was not found or
 * if an invalid value was passed.
 *
 * @function module:uci.cursor#list_append
 *
 * @param {string} config
 * The name of the configuration file to modify, e.g. `"firewall"` to
 * modify `/etc/config/firewall`.
 *
 * @param {string} section
 * The section name containing the list option to modify.
 *
 * @param {string} option
 * The list option name to add a value to.
 *
 * @param {string|boolean|int} value
 * The value to add to the list option.
 *
 * @returns {?boolean}
 *
 * @example
 * const ctx = cursor(…);
 *
 * // Add '192.168.1.1' to the 'dns' list in the 'lan' interface
 * ctx.list_append('network', 'lan', 'dns', '192.168.1.1');
 *
 * // Add a port to the first redirect section
 * ctx.list_append('firewall', '@redirect[0]', 'src_dport', '8080');
 */

/**
 * Remove an item from a list option in given configuration.
 *
 * Removes a single value from an existing list option within the specified section
 * of the given configuration. The configuration is implicitly loaded into the
 * cursor if not already present.
 *
 * If the specified value appears multiple times in the list, all matching occurrences
 * will be removed.
 *
 * Returns `true` if the item was successfully removed from the list.
 *
 * Returns `null` on error, e.g. if the targeted option was not found or if an
 * invalid value was passed.
 *
 * @function module:uci.cursor#list_remove
 *
 * @param {string} config
 * The name of the configuration file to modify, e.g. `"firewall"` to
 * modify `/etc/config/firewall`.
 *
 * @param {string} section
 * The section name containing the list option to modify.
 *
 * @param {string} option
 * The list option name to remove a value from.
 *
 * @param {string|boolean|int} value
 * The value to remove from the list option.
 *
 * @returns {?boolean}
 *
 * @example
 * const ctx = cursor(…);
 *
 * // Remove '8.8.8.8' from the 'dns' list in the 'lan' interface
 * ctx.list_remove('network', 'lan', 'dns', '8.8.8.8');
 *
 * // Remove a port from the first redirect section
 * ctx.list_remove('firewall', '@redirect[0]', 'src_dport', '8080');
 */

/**
 * Rename an option or section in given configuration.
 *
 * When invoked with four arguments, the function renames the given option
 * within the specified section of the given configuration to the provided
 * value.
 *
 * When invoked with three arguments, the function renames the entire specified
 * section to the provided value.
 *
 * In either case, the given configuration is implicitly loaded into the cursor
 * if not already present.
 *
 * Returns `true` if specified option or section has been renamed.
 *
 * Returns `null` on error, e.g. if the targeted configuration was not found or
 * if an invalid value was passed.
 *
 * @function module:uci.cursor#rename
 *
 * @param {string} config
 * The name of the configuration file to rename values in, e.g. `"system"` to
 * modify `/etc/config/system`.
 *
 * @param {string} section
 * The section name to rename or to rename an option in.
 *
 * @param {string} option_or_name
 * The option name to rename within the section or, when the subsequent name
 * argument is omitted, the new name of the renamed section within the
 * configuration.
 *
 * @param {string} [name]
 * The new name of the option to rename.
 *
 * @returns {?boolean}
 *
 * @example
 * const ctx = cursor(…);
 *
 * // Assign explicit name to last anonymous firewall rule section
 * ctx.rename('firewall', '@rule[-1]', 'my_block_rule');
 *
 * // Rename 'server' to 'orig_server_list' in ntp section of system config
 * ctx.rename('system', 'ntp', 'server', 'orig_server_list');
 *
 * // Rename 'wan' interface to 'external'
 * ctx.rename('network', 'wan', 'external');
 */

/**
 * Reorder sections in given configuration.
 *
 * The `reorder()` function moves a single section by repositioning it to the
 * given index within the configurations section list.
 *
 * The given configuration is implicitly loaded into the cursor if not already
 * present.
 *
 * Returns `true` if specified section has been moved.
 *
 * Returns `null` on error, e.g. if the targeted configuration was not found or
 * if an invalid value was passed.
 *
 * @function module:uci.cursor#reorder
 *
 * @param {string} config
 * The name of the configuration file to move the section in, e.g. `"system"` to
 * modify `/etc/config/system`.
 *
 * @param {string} section
 * The section name to move.
 *
 * @param {int} index
 * The target index to move the section to, starting from `0`.
 *
 * @returns {?boolean}
 *
 * @example
 * const ctx = cursor(…);
 *
 * // Query whole firewall config and reorder resulting dict by type and name
 * const type_order = ['defaults', 'zone', 'forwarding', 'redirect', 'rule'];
 * const values = ctx.get_all('firewall');
 *
 * sort(values, (k1, k2, s1, s2) => {
 *     // Get weight from type_order array
 *     let w1 = index(type_order, s1['.type']);
 *     let w2 = index(type_order, s2['.type']);
 *
 *     // For unknown type orders, use type value itself as weight
 *     if (w1 == -1) w1 = s1['.type'];
 *     if (w2 == -1) w2 = s2['.type'];
 *
 *     // Get name from name option, fallback to section name
 *     let n1 = s1.name ?? k1;
 *     let n2 = s2.name ?? k2;
 *
 *     // Order by weight
 *     if (w1 < w2) return -1;
 *     if (w1 > w2) return 1;
 *
 *     // For same weight order by name
 *     if (n1 < n2) return -1;
 *     if (n1 > n2) return 1;
 *
 *     return 0;
 * });
 *
 * // Sequentially reorder sorted sections in firewall configuration
 * let position = 0;
 *
 * for (let sid in values)
 *   ctx.reorder('firewall', sid, position++);
 */

/**
 * Save accumulated cursor changes to delta directory.
 *
 * The `save()` function writes consolidated changes made to in-memory copies of
 * loaded configuration files to the uci delta directory which effectively makes
 * them available to other processes using the same delta directory path as well
 * as the `uci changes` cli command when using the default delta directory.
 *
 * Note that uci deltas are overlayed over the actual configuration file values
 * so they're reflected by `get()`, `foreach()` etc. even if the underlying
 * configuration files are not actually changed (yet). The delta records may be
 * either permanently merged into the configuration by invoking `commit()` or
 * reverted through `revert()` in order to restore the current state of the
 * underlying configuration file.
 *
 * When the optional "config" parameter is omitted, delta records for all
 * currently loaded configuration files are written.
 *
 * In case that neither sharing changes with other processes nor any revert
 * functionality is required, changes may be committed directly using `commit()`
 * instead, bypassing any delta record creation.
 *
 * Returns `true` if operation completed successfully.
 *
 * Returns `null` on error, e.g. if the requested configuration was not loaded
 * or when a file system error occurred.
 *
 * @function module:uci.cursor#save
 *
 * @param {string} [config]
 * The name of the configuration file to save delta records for, e.g. `"system"`
 * to store changes for `/etc/config/system`.
 *
 * @returns {?boolean}
 *
 * @example
 * const ctx = cursor(…);
 *
 * ctx.set('wireless', '@wifi-iface[0]', 'disabled', '1');
 * ctx.save('wireless');
 *
 * @see {@link module:uci.cursor#commit|commit()}
 * @see {@link module:uci.cursor#revert|revert()}
 */

/**
 * Update configuration files with accumulated cursor changes.
 *
 * The `commit()` function merges changes made to in-memory copies of loaded
 * configuration files as well as existing delta records in the cursors
 * configured delta directory and writes them back into the underlying
 * configuration files, persistently committing changes to the file system.
 *
 * When the optional "config" parameter is omitted, all currently loaded
 * configuration files with either present delta records or yet unsaved
 * cursor changes are updated.
 *
 * Returns `true` if operation completed successfully.
 *
 * Returns `null` on error, e.g. if the requested configuration was not loaded
 * or when a file system error occurred.
 *
 * @function module:uci.cursor#commit
 *
 * @param {string} [config]
 * The name of the configuration file to commit, e.g. `"system"` to update the
 * `/etc/config/system` file.
 *
 * @returns {?boolean}
 *
 * @example
 * const ctx = cursor(…);
 *
 * ctx.set('system', '@system[0]', 'hostname', 'example.org');
 * ctx.commit('system');
 */

/**
 * Revert accumulated cursor changes and associated delta records.
 *
 * The `revert()` function discards any changes made to in-memory copies of
 * loaded configuration files and discards any related existing delta records in
 * the  cursors configured delta directory.
 *
 * When the optional "config" parameter is omitted, all currently loaded
 * configuration files with either present delta records or yet unsaved
 * cursor changes are reverted.
 *
 * Returns `true` if operation completed successfully.
 *
 * Returns `null` on error, e.g. if the requested configuration was not loaded
 * or when a file system error occurred.
 *
 * @function module:uci.cursor#revert
 *
 * @param {string} [config]
 * The name of the configuration file to revert, e.g. `"system"` to discard any
 * changes for the `/etc/config/system` file.
 *
 * @returns {?boolean}
 *
 * @example
 * const ctx = cursor(…);
 *
 * ctx.set('system', '@system[0]', 'hostname', 'example.org');
 * ctx.revert('system');
 *
 * @see {@link module:uci.cursor#save|save()}
 */

/**
 * Enumerate pending changes.
 *
 * The `changes()` function returns a list of change records for currently
 * loaded configuration files, originating both from the cursors associated
 * delta directory and yet unsaved cursor changes.
 *
 * When the optional "config" parameter is specified, the requested
 * configuration is implicitly loaded if it is not already loaded into the
 * cursor.
 *
 * Returns a dictionary of change record arrays, keyed by configuration name.
 *
 * Returns `null` on error, e.g. if the requested configuration could not be
 * loaded.
 *
 * @function module:uci.cursor#changes
 *
 * @param {string} [config]
 * The name of the configuration file to enumerate changes for, e.g. `"system"`
 * to query pending changes for the `/etc/config/system` file.
 *
 * @returns {?*}
 *
 * @example
 * const ctx = cursor(…);
 *
 * // Enumerate changes for all currently loaded configurations
 * const deltas = ctx.changes();
 *
 * // Explicitly load and enumerate changes for the "system" configuration
 * const deltas = ctx.changes('system');
 */

/**
 * Iterate configuration sections.
 *
 * The `foreach()` function iterates all sections of the given configuration,
 * optionally filtered by type, and invokes the given callback function for
 * each encountered section.
 *
 * When the optional "type" parameter is specified, the callback is only invoked
 * for sections of the given type, otherwise it is invoked for all sections.
 *
 * The requested configuration is implicitly loaded into the cursor.
 *
 * Returns `true` if the callback was executed successfully at least once.
 *
 * Returns `false` if the callback was never invoked, e.g. when the
 * configuration is empty or contains no sections of the given type.
 *
 * Returns `null` on error, e.g. when an invalid callback was passed or the
 * requested configuration not found.
 *
 * @function module:uci.cursor#foreach
 *
 * @param {string} config
 * The configuration to iterate sections for, e.g. `"system"` to read the
 * `/etc/config/system` file.
 *
 * @param {?string} type
 * Invoke the callback only for sections of the specified type.
 *
 * @param {function} callback
 * The callback to invoke for each section, will receive a section dictionary
 * as sole argument.
 *
 * @returns {?boolean}
 *
 * @example
 * const ctx = cursor(…);
 *
 * // Iterate all network interfaces
 * ctx.foreach('network', 'interface',
 * 	   section => print(`Have interface ${section[".name"]}\n`));
 */

/**
 * Enumerate existing configurations.
 *
 * The `configs()` function yields an array of configuration files present in
 * the cursors associated configuration directory, `/etc/config/` by default.
 *
 * Returns an array of configuration names on success.
 *
 * Returns `null` on error, e.g. due to filesystem errors.
 *
 * @function module:uci.cursor#configs
 *
 * @returns {?string[]}
 *
 * @example
 * const ctx = cursor(…);
 *
 * // Enumerate all present configuration file names
 * const configurations = ctx.configs();
 */

