
/**
 * Ütemezett függvény (óránként), ami frissíti az aktív metaadatokat.
 * Cél: A kliens oldali szűrés (N+1 query) kiváltása egyetlen olvasásra.
 * Skálázható megoldás 6000+ felhasználóhoz.
 */
exports.maintainActiveMetadata = onSchedule('every 60 minutes', async (event) => {
    console.log('Starting maintainActiveMetadata...');
    const science = 'Jogász'; // Jelenleg fix, később paraméterezhető

    // 1. Gyűjtés a 3 fő kollekcióból
    // Csak a 'Published' és 'Public' státuszúakat vesszük figyelembe a felhasználók számára
    const collections = ['notes', 'jogesetek', 'memoriapalota_allomasok'];
    const activeCategories = new Set();
    const activeTags = new Set();
    let totalDocsProcessed = 0;

    try {
        for (const collName of collections) {

            const snapshot = await db.collection(collName)
                .where('science', '==', science)
                .where('status', 'in', ['Published', 'Public'])
                .get();

            totalDocsProcessed += snapshot.size;

            snapshot.forEach(doc => {
                const data = doc.data();
                if (data.category && typeof data.category === 'string' && data.category.trim() !== '') {
                    activeCategories.add(data.category);
                }
                if (data.tags && Array.isArray(data.tags)) {
                    data.tags.forEach(tag => {
                        if (tag && typeof tag === 'string' && tag.trim() !== '') {
                            activeTags.add(tag);
                        }
                    });
                }
            });
        }

        // 2. Mentés aggregált dokumentumba
        // A dokumentum ID legyen 'jogasz_active', így a kliens könnyen megtalálja
        const outputDocId = 'jogasz_active';
        const categoriesList = Array.from(activeCategories).sort();
        const tagsList = Array.from(activeTags).sort();

        await db.collection('metadata').doc(outputDocId).set({
            categories: categoriesList,
            tags: tagsList,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            docsProcessed: totalDocsProcessed,
            source: 'cloud_function_maintainActiveMetadata'
        });

        console.log(`Updated active metadata (jogasz_active). Processed ${totalDocsProcessed} docs.`);
        console.log(`Active Categories: ${categoriesList.length}, Active Tags: ${tagsList.length}`);
        return null;
    } catch (error) {
        console.error('Error in maintainActiveMetadata:', error);
        return null;
    }
});
