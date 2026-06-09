import { callable, ConfirmModal, pluginSelf, showModal } from '@steambrew/client';

type OriginalOpenFunction = (url?: string | URL, target?: string, features?: string, replace?: boolean) => Window | null;
const originalOpen: OriginalOpenFunction = window.open;

const Patches = {
	TARGET_WINDOW_FLAG: [4114, 2],
	NEW_WINDOW_FLAG: 274,
};

window.open = function (url?: string | URL, target?: string, features?: string, replace?: boolean): Window | null {
	if (!url) {
		return originalOpen(url, target, features, replace);
	}

	const parsedUrl = new URL(url);
	const queryParams = parsedUrl.searchParams;

	const windowFeature = 'createflags';

	if (queryParams.has(windowFeature) && Patches.TARGET_WINDOW_FLAG.includes(parseInt(queryParams.get(windowFeature) || ''))) {
		queryParams.set(windowFeature, Patches.NEW_WINDOW_FLAG.toString());
		parsedUrl.search = queryParams.toString();
		url = parsedUrl.toString();
	}

	callable<[]>('PatchAllWindows')();
	return originalOpen(url, target, features, replace);
};

const ShowAlertMessage = (strTitle: string, strMessage: string) => showModal(<ConfirmModal strTitle={strTitle} strDescription={strMessage} />);

export default async function PluginMain() {
	pluginSelf.ShowAlertMessage = ShowAlertMessage;
	// Kitsune fix: patch the main Steam window (and any other already-open windows) on plugin load.
	// Upstream dwmx only patches via the window.open hook above, which misses the main window
	// since it's created natively by CEF before this hook runs.
	callable<[]>('PatchAllWindows')();
}
