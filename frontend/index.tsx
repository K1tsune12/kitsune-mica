import { callable, ConfirmModal, definePlugin, DialogControlsSection, IconsModule, pluginSelf, showModal } from '@steambrew/client';
import { UpdateCheckField } from './UpdateCheck';

type OriginalOpenFunction = (url?: string | URL, target?: string, features?: string, replace?: boolean) => Window | null;
const originalOpen: OriginalOpenFunction = window.open;

const Patches = {
	// 18 is the friends list and chat windows; 274 adds the flag that lets DWM blur show through.
	TARGET_WINDOW_FLAG: [4114, 2, 18],
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

	// The new window only exists after originalOpen returns, so patch afterwards.
	// The backend throttles calls to one per 3 s; the second pass catches windows
	// that open while a previous patch was still inside that window.
	const win = originalOpen(url, target, features, replace);
	setTimeout(() => callable<[]>('PatchAllWindows')(), 500);
	setTimeout(() => callable<[]>('PatchAllWindows')(), 3600);
	return win;
};

const ShowAlertMessage = (strTitle: string, strMessage: string) => showModal(<ConfirmModal strTitle={strTitle} strDescription={strMessage} />);

// Settings page in Millennium's sidebar. Mica has no options of its own yet,
// so the page only holds the update check.
const SettingsPanel = () => (
	<DialogControlsSection>
		<UpdateCheckField />
	</DialogControlsSection>
);

export default definePlugin(() => {
	pluginSelf.ShowAlertMessage = ShowAlertMessage;
	// Kitsune fix: patch the main Steam window (and any other already-open windows) on plugin load.
	// Upstream dwmx only patches via the window.open hook above, which misses the main window
	// since it's created natively by CEF before this hook runs.
	callable<[]>('PatchAllWindows')();
	return {
		title: 'Kitsune Mica',
		icon: <IconsModule.Settings />,
		content: <SettingsPanel />,
	} as any;
});
