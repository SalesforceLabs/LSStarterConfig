(() => {
    let actionName = env.getOption('actionName');
    let miId = record.stringValue('uid');

    async function hasQuestions() {
        let miqs = await db.query('InquiryQuestion', "InquiryId = '" + miId + "'");

        return {
            title: miqs && miqs.length ? 'success' : 'Please add Inquiry Questions',
            isValid: miqs && miqs.length
        };
    }

    async function isSigned() {
        let digitalSig = await db.query('DigitalSignature', "ParentId = '" + miId + "'");

        return {
            title: digitalSig && digitalSig.length ? 'success' : 'Please provide a signature',
            isValid: digitalSig && digitalSig.length
        };
    }

    async function isRespPrefAdded() {
        let mi = await db.rowById('Inquiry', miId);

        return {
            title: 'MIRF_add_response_preference',
            status: mi.stringValue('ResponseContactPointRecId') ? 'success' : 'error'
        };
    }

    async function hasAnswers() {
        let miqs = await db.query('InquiryQuestion', "InquiryId = '" + miId + "'");

        let miqIds = miqs.map((row) => row.stringValue('uid'));

        let miansws = await db.query(
            'InquiryQuestionAnswer',
            await new ConditionBuilder('InquiryQuestionAnswer', new AndCondition().add(new SetCondition('InquiryQuestionId', 'IN', miqIds))).build()
        );

        let qsAnsws = miqs.map((row) => miansws.filter((r) => row.stringValue('uid') === r.stringValue('InquiryQuestionId')).length);

        return {
            title: 'Add Anserws',
            status: miansws.length && qsAnsws.every((i) => i > 0) ? 'success' : 'error'
        };
    }

    async function hasDuplicateTopics() {
        const mits = await db.query('SubjectAssignment', "AssignmentId = '" + miId + "'");

        const topicIds = mits.map((row) => row.stringValue('SubjectId'));
        return {
            title: 'Please remove duplicate topics',
            status: new Set(topicIds).size === topicIds.length ? 'success' : 'error'
        };
    }

    let result = [];

    switch (actionName) {
        case 'Add_signature':
            result = [hasQuestions(), hasDuplicateTopics(), isRespPrefAdded()];
            break;

        case 'Submit':
            result = [isSigned()];
            break;

        case 'Move_Status_to_Responded':
            result = [hasAnswers(), hasDuplicateTopics()];
            break;

        default:
            result = [];
    }

    return result;
})();
