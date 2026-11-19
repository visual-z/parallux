package aggregate

// dialFailure says whether a failed dial should try the next link and
// whether it is evidence against this link (fix-dial-errors-poison-health). stub
func dialFailure(err error) (retry bool, linkDown bool) {
	return true, true
}
