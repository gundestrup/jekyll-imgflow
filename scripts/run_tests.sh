#!/bin/bash
# Test Runner Wrapper Script for ImgFlow

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_LOGGER="$SCRIPT_DIR/test_logger.rb"

echo -e "${BLUE}🧪 ImgFlow Test Runner${NC}"
echo -e "${BLUE}=====================${NC}"

# Check if test logger exists
if [ ! -f "$TEST_LOGGER" ]; then
    echo -e "${RED}❌ Error: test_logger.rb not found at $TEST_LOGGER${NC}"
    exit 1
fi

# Handle different commands
case "$1" in
    "status")
        echo -e "${YELLOW}📊 Showing test status...${NC}"
        ruby "$TEST_LOGGER" status
        ;;
    "help"|"-h"|"--help")
        echo "Usage: $0 [command] [test_spec] [options]"
        echo ""
        echo "Commands:"
        echo "  status              Show test status dashboard"
        echo "  help                Show this help"
        echo ""
        echo "Test Running:"
        echo "  $0                  Run all tests with logging"
        echo "  $0 [test_spec]      Run specific test file"
        echo "  $0 --quiet          Run tests with minimal output"
        echo ""
        echo "Examples:"
        echo "  $0                              # Run all tests"
        echo "  $0 spec/production_mode_spec.rb # Run production mode tests"
        echo "  $0 status                        # Show test status"
        echo "  $0 --quiet                       # Run tests quietly"
        ;;
    "")
        echo -e "${YELLOW}🧪 Running all tests with logging...${NC}"
        ruby "$TEST_LOGGER"
        ;;
    *)
        echo -e "${YELLOW}🧪 Running tests with logging: $@${NC}"
        ruby "$TEST_LOGGER" "$@"
        ;;
esac
