-- Requirements table for access control
CREATE TABLE public.requirements (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    date DATE NOT NULL,
    requirement VARCHAR(255) NOT NULL
);

-- Insert test data: different dates have different access requirements
-- Some dates have multiple requirements (user needs ALL of them)
INSERT INTO public.requirements (date, requirement) VALUES
    -- Jan 1: needs admin only
    ('2024-01-01', 'admin'),

    -- Jan 2: needs analyst only
    ('2024-01-02', 'analyst'),

    -- Jan 3: needs public only (everyone should have this)
    ('2024-01-03', 'public'),

    -- Jan 4: needs BOTH admin AND analyst
    ('2024-01-04', 'admin'),
    ('2024-01-04', 'analyst'),

    -- Jan 5: needs admin, analyst, AND public (all three)
    ('2024-01-05', 'admin'),
    ('2024-01-05', 'analyst'),
    ('2024-01-05', 'public'),

    -- Jan 6: needs secret (nobody should have this in our test)
    ('2024-01-06', 'secret'),

    -- Jan 7: needs secret AND admin (even admins can't see this)
    ('2024-01-07', 'secret'),
    ('2024-01-07', 'admin');
