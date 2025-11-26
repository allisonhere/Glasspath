package cmd

import (
	"bytes"
	"fmt"
	"os/exec"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/spf13/cobra"
)

type commandMsg struct {
	title  string
	output string
	err    error
}

type model struct {
	service string
	log     string
	err     error
}

func newCommand(service string, title string, args ...string) tea.Cmd {
	return func() tea.Msg {
		cmd := exec.Command(args[0], args[1:]...)
		var buf bytes.Buffer
		cmd.Stdout = &buf
		cmd.Stderr = &buf
		err := cmd.Run()
		return commandMsg{title: title, output: buf.String(), err: err}
	}
}

func bold(s string) string {
	return "\033[1m" + s + "\033[0m"
}

func dim(s string) string {
	return "\033[2m" + s + "\033[0m"
}

func initialCmd(service string) tea.Cmd {
	return newCommand(service, fmt.Sprintf("Status (%s)", service), "systemctl", "status", service, "--no-pager")
}

func (m model) Init() tea.Cmd {
	return initialCmd(m.service)
}

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case commandMsg:
		if msg.err != nil {
			m.log = fmt.Sprintf("%s\n\nError:\n%s", msg.title, msg.err.Error())
		} else {
			m.log = fmt.Sprintf("%s\n\n%s", msg.title, msg.output)
		}
		return m, nil
	case tea.KeyMsg:
		switch msg.String() {
		case "ctrl+c", "q":
			return m, tea.Quit
		case "s":
			return m, newCommand(m.service, fmt.Sprintf("Status (%s)", m.service), "systemctl", "status", m.service, "--no-pager")
		case "r":
			return m, newCommand(m.service, fmt.Sprintf("Restart (%s)", m.service), "systemctl", "restart", m.service)
		case "l":
			return m, newCommand(m.service, fmt.Sprintf("Logs (%s, last 50)", m.service), "journalctl", "-u", m.service, "--no-pager", "-n", "50")
		}
	}
	return m, nil
}

func (m model) View() string {
	title := bold(fmt.Sprintf("Glasspath TUI (service: %s)", m.service))
	help := dim("Keys: s=status • r=restart • l=logs • q=quit")
	border := strings.Repeat("─", 60)
	body := m.log
	if strings.TrimSpace(body) == "" {
		body = dim("Waiting... press s for status, r to restart, l for logs.")
	}
	return fmt.Sprintf("%s\n%s\n%s\n\n%s\n", title, border, help, body)
}

func newTUICmd() *cobra.Command {
	var serviceName string

	cmd := &cobra.Command{
		Use:   "tui",
		Short: "Interactive terminal UI for Glasspath service management",
		RunE: func(_ *cobra.Command, _ []string) error {
			if serviceName == "" {
				serviceName = "glasspath"
			}
			p := tea.NewProgram(model{service: serviceName})
			_, err := p.Run()
			return err
		},
	}

	cmd.Flags().StringVar(&serviceName, "service", "glasspath", "systemd service name to manage")
	return cmd
}

func init() {
	rootCmd.AddCommand(newTUICmd())
}
