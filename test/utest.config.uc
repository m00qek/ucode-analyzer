return {
	lib_paths: [ "../src", "helpers" ],
	mocks: { fs: null },
	// Per test file. Each e2e test starts a server that indexes this repo
	// (~3.5 s); lifecycle_test alone takes ~35 s, and 8 parallel workers on a
	// busy host pushed it past utest's 60 s default.
	timeout: 300,
};
