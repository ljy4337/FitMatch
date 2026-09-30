-- REVIEW ONLY: source metadata extraction, not a complete dump. Not applied.
CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION handle_new_user();
