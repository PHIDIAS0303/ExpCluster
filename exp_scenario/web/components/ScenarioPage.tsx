
export default function ScenarioPage() {
	const account = useAccount();
	return <PageLayout nav={[{ name: "Scenario Display" }]}>
		<PageHeader
			title="Display"
			extra={account.hasPermission("exp_scenario.gui.vlayer") ? <CreateReportButton /> : undefined}
		/>
		<ReportsTable />
	</PageLayout>;
}
