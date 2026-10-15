// Open state of the Functions window, shared by the places that open it
// (the reference popover of an expression input) and the app that shows it.

export const functionsRef = $state<{ open: boolean; query: string; nonce: number }>({ open: false, query: "", nonce: 0 });

export function openFunctions(query = "") {
	functionsRef.query = query;
	functionsRef.open = true;
	functionsRef.nonce++;
}

export function closeFunctions() {
	functionsRef.open = false;
}
