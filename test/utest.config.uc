return {
	lib_paths: [ "../src", "helpers" ],
	mocks: { fs: null },
	// Per test file. e2e tests start servers on the fixture workspace (~0.3 s
	// each); the slowest file takes ~6 s alone, more on a busy host with 8
	// parallel workers, so stay well above that.
	timeout: 120,
};
